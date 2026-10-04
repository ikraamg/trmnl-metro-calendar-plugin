# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/temperature-unit.spec.js. trmnlp fills temperature_unit with its settings.yml
# default (c) where his runs left it out, as TRMNL's form does; the cases' answers are the same.
RSpec.describe 'temperature-unit' do
  include TransformC::Helpers

  let(:now) { '2026-09-09T09:00:00Z' }
  let(:ics) { TransformC.ics_with_events([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }]) }
  # Open-Meteo converts server-side, so which unit was ASKED for is the thing to assert.
  let(:forecast) do
    JSON.generate(daily: { temperature_2m_max: [70], temperature_2m_min: [55], precipitation_probability_max: [10],
                           weathercode: [0], sunrise: ['2026-09-09T07:05'], sunset: ['2026-09-09T19:45'] },
                  hourly: { time: [], precipitation_probability: [] })
  end

  def board(config_extra, fields = {}, forecast_answer: forecast, state: nil)
    config = JSON.generate({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }] }.merge(config_extra))
    run_transform(now:, fields: { use_demo_data: 'false', lat_lon: '51.05,3.72', config_json: config }.merge(fields),
                  mocks: { Metro::FORECAST => forecast_answer, '*' => ics }, state:)
  end

  def weather_url(run) = TransformC.urls(run).find { it.include?('api.open-meteo.com') } || ''

  def unit(run) = TransformC.payload(run)['header_weather']['unit']

  it 'a board that still has auto stored keeps it: en-US Fahrenheit, elsewhere Celsius' do
    us = board({ locale: 'en-US' }, { temperature_unit: 'auto' })
    expect(weather_url(us)).to match(/temperature_unit=fahrenheit/), "en-US should ask for Fahrenheit: #{weather_url(us)}"

    gb = board({ locale: 'en-GB' }, { temperature_unit: 'auto' })
    expect(weather_url(gb)).to match(/temperature_unit=celsius/), "en-GB should ask for Celsius: #{weather_url(gb)}"
    expect(unit(gb)).to eq('C'), 'the payload should say which unit it is in'
  end

  it 'a board that chose nothing gets the declared default, not a guess' do
    run = board({ locale: 'en-US' })

    expect(weather_url(run)).to match(/temperature_unit=celsius/), "an unset unit should be Celsius, not guessed: #{weather_url(run)}"
    expect(unit(run)).to eq('C')
  end

  it 'the config wins over the account setting, the way timeFormat does' do
    run = board({ locale: 'en-US', temperatureUnit: 'celsius' }, { temperature_unit: 'f' })

    expect(weather_url(run)).to match(/temperature_unit=celsius/), "the config was overruled: #{weather_url(run)}"
    expect(unit(run)).to eq('C')
  end

  it 'the account setting is used when the config says nothing' do
    run = board({ locale: 'nl-BE' }, { temperature_unit: 'f' })

    expect(weather_url(run)).to match(/temperature_unit=fahrenheit/), "the setting was ignored: #{weather_url(run)}"
    expect(unit(run)).to eq('F')
  end

  it 'an unrecognised unit is the default, not a guess' do
    run = board({ locale: 'en-US', temperatureUnit: 'kelvin' })

    expect(weather_url(run)).to match(/temperature_unit=celsius/), "\"kelvin\" should fall to the default: #{weather_url(run)}"
  end

  it 'weather replayed from state is converted, not shown in the old unit' do
    state = { weather: { hi: 21, lo: 13, condition: 'clear', icon: 'wi-day-sunny.svg', rain_chance: 10, unit: 'C', milestones: [], sun: [] },
              weatherFetchedAt: Time.iso8601(now).to_i - 600 }
    # the forecast's connection is dropped: the fetch throws
    run = board({ locale: 'en-US' }, { temperature_unit: 'f' }, forecast_answer: { error: :reset }, state:)

    expect(TransformC.payload(run)['header_weather']).to include('hi' => 70, 'lo' => 55),
                                                         "expected 21/13 C converted to 70/55 F, got #{TransformC.payload(run)['header_weather']}"
  end
end
