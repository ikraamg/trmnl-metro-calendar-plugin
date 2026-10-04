# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/wind.spec.js.
RSpec.describe 'wind' do
  include TransformC::Helpers

  let(:hours) { %w[2026-09-09 2026-09-10].flat_map { |day| (0..23).map { format('%<day>sT%<hour>02d:00', day:, hour: it) } } }

  def forecast(gusts)
    JSON.generate(
      daily: { time: %w[2026-09-09 2026-09-10], temperature_2m_max: [20, 21], temperature_2m_min: [11, 12],
               precipitation_probability_max: [5, 5], weathercode: [1, 1],
               sunrise: %w[2026-09-09T07:05 2026-09-10T07:07], sunset: %w[2026-09-09T19:58 2026-09-10T19:56] },
      hourly: { time: hours, precipitation_probability: [5] * hours.size, weathercode: [1] * hours.size,
                temperature_2m: [18] * hours.size, wind_gusts_10m: hours.map { gusts.call(it) } }
    )
  end

  def board_with(gusts)
    standup = TransformC.ics_with_events([{ start: '20260909T090000Z', end: '20260909T100000Z', summary: 'Standup' }])
    run_transform(now: '2026-09-09T08:00:00Z', fields: { config_json: 'https://calendar.example.com/a.ics', lat_lon: '51.05,3.72' },
                  mocks: { Metro::FORECAST => forecast(gusts), '*' => standup })
  end

  it 'the first gusty hour of a day is a windy mark, and a calm day has none' do
    # gusts of 60 from 14:00 today and from 09:00 tomorrow
    run = board_with(lambda do |time|
      hour = time[11, 2].to_i
      day = time[0, 10]
      (day == '2026-09-09' && hour >= 14) || (day == '2026-09-10' && hour >= 9) ? 60 : 20
    end)
    data = TransformC.payload(run)
    asked = TransformC.urls(run).find { it.include?('api.open-meteo.com') } || ''
    today = data['weather'].select { it['kind'] == 'windy' }
    tomorrow = (data['days'][1] || {}).dig('weather', 'milestones') || []

    expect(asked).to(match(/wind_gusts_10m/).and(match(/wind_speed_unit=kmh/)), "the forecast is not asked for gusts in km/h: #{asked}")
    expect(today).to match([include('at_min' => 14 * 60, 'icon' => /wi-strong-wind\.svg\z/)]), "today's windy mark: #{today}"
    expect(today[0]['label']).to match(/\AWindy /), "the label: #{today[0]['label']}"
    expect(tomorrow).to include(include('kind' => 'windy', 'atMin' => 9 * 60)), "tomorrow's windy mark: #{tomorrow}"

    calm = TransformC.payload(board_with(->(_) { 30 }))
    expect(calm['weather'].map { it['kind'] }).not_to include('windy'), 'a calm day was marked windy'
  end
end
