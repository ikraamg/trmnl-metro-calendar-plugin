# frozen_string_literal: true

require_relative 'support/metro'

# Ported from test/trmnl/transform/saved-state.spec.js.
RSpec.describe 'Saved state' do
  let(:now) { '2026-09-09T09:00:00Z' }
  let(:ics_url) { 'https://cloud.example.com/cal-2.ics' }
  let(:feed) do
    Metro.ics([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }], calendar_name: 'Alex Personal')
  end
  let(:forecast) do
    { daily: { temperature_2m_max: [21], temperature_2m_min: [12], precipitation_probability_max: [40],
               weathercode: [61], sunrise: ['2026-09-09T07:05'], sunset: ['2026-09-09T19:45'] },
      hourly: { time: %w[2026-09-09T13:00 2026-09-09T14:00], precipitation_probability: [80, 10] } }
  end
  let(:fields) { Metro.fields(config_json: JSON.generate(calendars: [{ url: ics_url }])) }

  def network(weather_fails: false, calendars_fail: false)
    { Metro::FORECAST => weather_fails ? { status: 503 } : { json: forecast },
      Metro::I18N => { status: 404 },
      '*' => calendars_fail ? { status: 500 } : feed }
  end

  def transform(state: nil, **network_options)
    trmnl.transform(now:, custom_fields: fields, variables: Metro.variables, state:, mocks: network(**network_options))
  end

  it 'hands saved state back to the runtime, not just the board' do
    run = transform
    expect([run.error, run.state.class, run.data.key?('data')]).to eq([nil, Hash, true])
  end

  it 'keeps the last good forecast and replays it when the weather API fails' do
    good = transform
    later = transform(state: good.state, weather_fails: true)

    expect(later.data.dig('data', 'header_weather', 'hi')).to eq(good.data.dig('data', 'header_weather', 'hi'))
  end

  it 'replays the forecast markers too, without a sun' do
    later = transform(state: transform.state, weather_fails: true)
    marks = later.data.dig('data', 'weather')

    expect(marks).to(be_any.and(all(include('type' => 'weather'))))
  end
end
