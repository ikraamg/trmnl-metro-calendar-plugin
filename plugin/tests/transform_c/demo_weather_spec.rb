# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/demo-weather.spec.js.
RSpec.describe 'demo-weather' do
  include TransformC::Helpers

  let(:now) { '2026-09-09T09:00:00Z' }
  let(:sets) { %w[simpsons futurama friends] }
  let(:standup) { TransformC.ics_with_events([{ start: '20260909T090000Z', end: '20260909T100000Z', summary: 'Standup' }]) }

  def forecast_urls(run) = TransformC.urls(run).select { it.include?('api.open-meteo.com') }

  def demo_board(set) = run_transform(now:, fields: { use_demo_data: 'true', demo_set: set }, mocks: TransformC.demo_mocks(i18n: false))

  %w[simpsons futurama friends].each do |set|
    it "the \"#{set}\" demo board draws a full sky band with no network weather" do
      run = demo_board(set)
      data = TransformC.payload(run)
      labels = data['weather'].select { it['type'] == 'weather' }.map { it['label'] }

      expect(forecast_urls(run)).to be_empty, "#{set}: the demo asked the weather API for a board that has no location"
      expect(data['weather']).to all(include('type' => 'weather')),
                                 "#{set}: the sky band carries something that is not a weather marker: " \
                                 "#{data['weather'].map { it['type'] }}"
      expect(labels).to include(/^Rain starts/), "#{set}: no rain start marker, got #{labels}"
      expect(labels).to include(/^Rain stops/), "#{set}: no rain stop marker, got #{labels}"
      expect(labels).to include(/^(Snow|Storms|Foggy)/), "#{set}: no snow/storm/fog marker, got #{labels}"
      expect(data['header_weather']).to include('hi' => be, 'condition' => be),
                                        "#{set}: the header has no weather: #{data['header_weather']}"
      expect(data['weather'].map { it['icon'] })
        .to all(match(%r{\Ahttps://trmnl\.com/images/plugins/weather/wi-[a-z-]+\.svg\z})), "#{set}: bad marker icon"
    end
  end

  it 'between them the demo boards exercise every heavy condition' do
    heavy = sets.flat_map do |set|
      TransformC.payload(demo_board(set))['weather'].select { it['type'] == 'weather' }
                .filter_map { it['label'][/\A(Snow|Storms|Foggy)/, 1] }
    end.uniq

    expect(heavy.size).to eq(3), "expected snow, storms and fog across the three boards, got #{heavy.join(', ')}"
  end

  it "sunrise and sunset come back as a day's dark hours, never as sky markers" do
    forecast = JSON.generate(
      daily: { temperature_2m_max: [20, 22], temperature_2m_min: [10, 11], precipitation_probability_max: [10, 5],
               weathercode: [0, 1], sunrise: %w[2026-09-09T07:05 2026-09-10T07:07],
               sunset: %w[2026-09-09T19:58 2026-09-10T19:56], time: %w[2026-09-09 2026-09-10] },
      hourly: { time: [], precipitation_probability: [] }
    )
    run = run_transform(now:, fields: { config_json: 'https://calendar.example.com/a.ics', lat_lon: '51.05,3.72' },
                        mocks: { Metro::FORECAST => forecast, '*' => standup })
    data = TransformC.payload(run)
    first_day = (data['days'] || [])[0]

    expect(forecast_urls(run).first).to(match(/sunrise/).and(match(/sunset/)), 'the forecast query does not ask for the sun')
    expect(first_day&.dig('weather')).to include('sunrise_min' => 425, 'sunset_min' => 1198),
                                         "the day does not carry its sunrise and sunset: #{first_day&.dig('weather')}"
    expect(data['weather'].map { it['label'] || '' }).not_to include(/sun/i), 'a sunrise or sunset marker came back'
  end

  it 'the offline demo fallback keeps its weather too' do
    data = TransformC.payload(run_transform(now:, fields: { use_demo_data: 'true' }, mocks: { '*' => { status: 500 } }))

    expect(data['weather'].count { it['type'] == 'weather' }).to be >= 2, 'the offline demo lost its weather markers'
    expect(data['weather']).to all(include('type' => 'weather')), 'the offline demo grew a marker that is not weather'
  end

  it 'demo weather does not leak into a real board that has no location' do
    feed = TransformC.ics_with_events([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }])
    config = JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }])
    data = TransformC.payload(run_transform(now:, fields: { use_demo_data: 'false', config_json: config }, mocks: { '*' => feed }))

    expect(data['header_weather']['hi']).to be_nil, "a real board invented a temperature: #{data['header_weather']}"
    expect(data['weather']).to be_empty, 'a real board with no location drew sky markers'
  end

  it 'a demo board with a real location prefers the real forecast' do
    forecast = JSON.generate(
      daily: { temperature_2m_max: [30], temperature_2m_min: [20], precipitation_probability_max: [5], weathercode: [0],
               sunrise: ['2026-09-09T06:30'], sunset: ['2026-09-09T20:30'] },
      hourly: { time: [], precipitation_probability: [] }
    )
    mocks = { Metro::FORECAST => forecast }.merge(TransformC.demo_mocks(i18n: false))
    data = TransformC.payload(run_transform(now:, fields: { use_demo_data: 'true', lat_lon: '51.05,3.72' }, mocks:))

    expect(data['header_weather']['hi']).to eq(30), "the demo weather overrode a real forecast: #{data['header_weather']}"
    expect(data['weather']).to all(include('type' => 'weather')),
                               "the real forecast put a sun marker back on the board: #{data['weather']}"
  end

  it "the example day asks for the sun in the location's own clock; a real day does not" do
    forecast = JSON.generate(
      daily: { temperature_2m_max: [24], temperature_2m_min: [14], precipitation_probability_max: [0], weathercode: [0],
               sunrise: ['2026-09-09T06:36'], sunset: ['2026-09-09T19:04'], time: ['2026-09-09'] },
      hourly: { time: [], precipitation_probability: [] }
    )
    mocks = { Metro::FORECAST => forecast }.merge(TransformC.demo_mocks(i18n: false)).merge('*' => standup)

    demo = run_transform(now:, fields: { use_demo_data: 'true', lat_lon: '40.71,-74.00' }, mocks:)
    expect(forecast_urls(demo).first).to match(/timezone=auto/), "the example day asked in the account zone: #{forecast_urls(demo).first}"

    real = run_transform(now:, fields: { config_json: 'https://calendar.example.com/a.ics', lat_lon: '40.71,-74.00' }, mocks:)
    expect(forecast_urls(real).first).not_to match(/timezone=auto/), "a real day lost the account zone: #{forecast_urls(real).first}"
    expect(TransformC.payload(real)['days'][0]['weather'] || {}).to include('sunrise_min' => 396),
                                                                   'the real day should keep the true sunrise'
  end
end
