# frozen_string_literal: true

require_relative '../support/transform_b'

# Ported from test/trmnl/transform/multi-day.spec.js.
RSpec.describe 'multi-day' do
  include TransformBHelpers

  day = TransformB::DAY
  tomorrow = { start: '20260910T040000Z', end: '20260910T050000Z', summary: 'Tomorrow' }
  busy_today = [
    { start: '20260909T090000Z', end: '20260909T093000Z', summary: 'Standup' },
    { start: '20260909T110000Z', end: '20260909T120000Z', summary: 'Workshop' },
    { start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Today' }
  ]
  both = TransformB.ics([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Today Meeting' },
                         { start: '20260910T090000Z', end: '20260910T100000Z', summary: 'Tomorrow Meeting' }])

  let(:now) { '2026-09-09T09:00:00Z' } # a Wednesday
  let(:forecast) do
    { daily: { temperature_2m_max: [18, 21, 15], temperature_2m_min: [11, 13, 9],
               precipitation_probability_max: [10, 80, 40], weathercode: [0, 61, 3],
               sunrise: ['2026-09-09T06:30'], sunset: ['2026-09-09T20:30'] },
      hourly: { time: [], precipitation_probability: [] } }
  end

  # Two days of hourly probabilities, 07:00-21:00 each: today rains from 13:00 on, tomorrow 09:00 to 12:00.
  let(:two_day_forecast) do
    hours = { '2026-09-09' => ->(hh) { hh >= 13 }, '2026-09-10' => ->(hh) { hh >= 9 && hh < 12 } }
    time = hours.keys.flat_map { |date| (7..21).map { format('%sT%02d:00', date, it) } }
    chance = hours.values.flat_map { |wet| (7..21).map { wet.(it) ? 80 : 5 } }
    { daily: { temperature_2m_max: [18, 21], temperature_2m_min: [11, 13], precipitation_probability_max: [80, 80],
               weathercode: [61, 61], sunrise: %w[2026-09-09T06:30 2026-09-10T06:32],
               sunset: %w[2026-09-09T20:30 2026-09-10T20:27] },
      hourly: { time:, precipitation_probability: chance } }
  end

  def fields(extra = {})
    { lat_lon: '51.05,3.72', config_json: JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }]) }
      .merge(extra)
  end

  def on(events, at: now, weather: forecast, **extra)
    ics = events.is_a?(String) ? events : TransformB.ics(events)
    board(now: at, fields: fields(extra), mocks: { Metro::FORECAST => JSON.generate(weather), '*' => ics })
  end

  def titles(data) = data['events'].map { it['title'] }
  def sky(data, kind) = data['weather'].select { it['type'] == kind }.map { it['at_min'] }

  it 'the payload describes both days, and the client picks between them' do
    busy = on(busy_today)
    quiet = on([busy_today[2], tomorrow])

    expect([busy['days'].map { it['start_min'] }, quiet['days'].size]).to eq([[0, day], 2]),
                                                                          'both days should be sent, from midnight, ' \
                                                                          'a day apart, whatever gets drawn'
  end

  it 'the day being drawn is rebased onto its own midnight' do
    data = on(busy_today)
    event = data['events'].find { it['title'] == 'Today' }

    expect([event&.fetch('start_min'), data['days'][0].values_at('start_min', 'end_min')]).to eq([14 * 60, [0, day]])
  end

  it 'a busy board draws today and nothing else' do
    data = on(busy_today + [{ start: '20260910T090000Z', end: '20260910T100000Z', summary: 'Tomorrow Meeting' }])
    meeting = data['events'].find { it['title'] == 'Tomorrow Meeting' }

    expect([titles(data).sort, meeting['start_min']])
      .to eq([['Standup', 'Today', 'Tomorrow Meeting', 'Workshop'], day + (9 * 60)]),
          "the payload should carry both days, tomorrow's meeting at tomorrow's nine"
  end

  it 'a recurrence is evaluated against the day it lands on' do
    rec = { start: '20260903T050000Z', end: '20260903T051500Z', summary: 'Thursday Standup', rrule: 'FREQ=WEEKLY;BYDAY=TH' }
    standups = ->(data) { data['events'].select { it['title'] == 'Thursday Standup' }.map { it['start_min'] } }

    expect([standups.(on(busy_today + [rec])), standups.(on([rec]))]).to eq([[day + (5 * 60)], [day + (5 * 60)]]),
                                                                          "a Thursday standup is wearing Wednesday's " \
                                                                          'minutes, or is missing'
  end

  it 'the window stays inside the day being drawn, unless the board rolled' do
    data = on(busy_today + [{ start: '20260909T060000Z', end: '20260909T070000Z', summary: 'Early' },
                            { start: '20260909T220000Z', end: '20260909T230000Z', summary: 'Late' }])

    expect(data).to include('day_start_min' => be >= 0, 'day_end_min' => (be <= 2 * day).and(be > data['day_start_min']))
  end

  it 'the forecast is the one for the day it is about' do
    busy = on(busy_today)
    quiet = on([busy_today[2], tomorrow])

    expect([busy['header_weather']['hi'], busy['days'][0]['weather']['hi'], quiet['days'].size,
            quiet['days'][1]['weather']['hi']]).to eq([18, 18, 2, 21])
  end

  it 'the board is always about today, and says so' do
    data = on(busy_today)

    expect([data['date_label'], data['now_min']]).to all(be_truthy)
  end

  it 'the board reaches tomorrow by rolling, not by giving up on today' do
    skip 'stays in the Node runner: asserts where the board opens through the solver (opened, solver/day.js)'
  end

  it 'rain markers start and stop within one day, in that order' do
    data = on(both, weather: two_day_forecast)
    labels = data['weather'].select { it['type'] == 'weather' }.map { it['label'] }

    expect([sky(data, 'weather'), labels.first]).to match([[13 * 60], /Rain Starts/i])
  end

  it 'the sky belongs to the day the board opens on' do
    data = on(both, weather: two_day_forecast)

    expect([sky(data, 'sun'), sky(data, 'weather').size.positive?]).to eq([[], true])
  end

  it 'the board carries the clock, because it is about now' do
    expect(on(both, weather: two_day_forecast)['now_min']).to eq(9 * 60)
  end

  it 'the day on the board carries its own forecast in days[0]' do
    data = on(both, weather: two_day_forecast)

    expect([data['days'][0]['weather']&.fetch('hi'), data['header_weather']['hi']]).to eq([18, 18])
  end

  it "a sunset after the board's midnight is counted into the next day, not wrapped to 1am of this one" do
    weather = { daily: { time: %w[2026-09-09 2026-09-10], temperature_2m_max: [24, 25], temperature_2m_min: [13, 14],
                         precipitation_probability_max: [0, 0], weathercode: [1, 1],
                         sunrise: %w[2026-09-09T12:36 2026-09-10T12:37], sunset: %w[2026-09-10T01:04 2026-09-11T01:03] },
                hourly: { time: [], precipitation_probability: [] } }

    expect(on(both, weather:)['days'][0]['weather'].values_at('sunrise_min', 'sunset_min')).to eq([756, 1504])
  end
end
