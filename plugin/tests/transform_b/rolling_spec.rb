# frozen_string_literal: true

require_relative '../support/transform_b'

# Ported from test/trmnl/transform/rolling.spec.js.
RSpec.describe 'rolling' do
  include TransformBHelpers

  day = TransformB::DAY
  solver = 'stays in the Node runner: asserts where the board opens through the solver (opened, solver/day.js)'
  quiet_rows = [
    ['20260909', '1400', '1500', 'Dentist'],
    ['20260910', '0500', '0600', 'Early Flight'],
    ['20260910', '1900', '2000', 'Book Club']
  ]

  let(:now) { '2026-09-09T09:00:00Z' } # a Wednesday
  let(:forecast) do
    JSON.generate(daily: { temperature_2m_max: [18, 21], temperature_2m_min: [11, 13],
                           precipitation_probability_max: [10, 80], weathercode: [0, 61],
                           sunrise: %w[2026-09-09T06:30 2026-09-10T06:32], sunset: %w[2026-09-09T20:30 2026-09-10T20:27] },
                  hourly: { time: [], precipitation_probability: [] })
  end

  # events written as [YYYYMMDD, "HHMM", "HHMM", title]
  def feed(rows) = TransformB.ics(rows.map { |date, from, to, title| { start: "#{date}T#{from}00Z", end: "#{date}T#{to}00Z", summary: title } })

  def fields(extra = {})
    { lat_lon: '51.05,3.72', config_json: JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }]) }
      .merge(extra)
  end

  def on(rows_or_ics, at: now, **extra)
    ics = rows_or_ics.is_a?(String) ? rows_or_ics : feed(rows_or_ics)
    board(now: at, fields: fields(extra), mocks: { Metro::FORECAST => forecast, '*' => ics })
  end

  def titles(data) = data['events'].map { it['title'] }

  it 'a quiet day borrows tomorrow, and from ten so does a busy one' do
    skip solver
  end

  it 'three lines at one dinner is one event, not three' do
    shared = JSON.generate(lines: [{ name: 'Ada' }, { name: 'Bo' }, { name: 'Cy' }],
                           calendars: [{ url: 'https://example.com/a.ics',
                                         rules: [{ match: { type: 'contains', value: 'Dinner' }, line: %w[Ada Bo Cy] }] }])
    data = on([['20260909', '1800', '1900', 'Family Dinner'], ['20260910', '0500', '0600', 'Early Flight']],
              config_json: shared)

    expect(data['days'].size).to eq(2), 'a shared dinner was counted once per line'
  end

  it 'an all-day state is not an event on the scale of hours' do
    ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" \
          "BEGIN:VEVENT\r\nUID:h\r\nDTSTART;VALUE=DATE:20260909\r\nDTEND;VALUE=DATE:20260912\r\n" \
          "SUMMARY:Half Term\r\nEND:VEVENT\r\n" \
          "BEGIN:VEVENT\r\nUID:t\r\nDTSTART:20260910T090000Z\r\nDTEND:20260910T100000Z\r\n" \
          "SUMMARY:Sprint Review\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    data = on(ics)

    expect([data['days'].size, data['all_day'].map { it['title'] }]).to eq([2, ['Half Term']]),
                                                                        'an all-day entry was counted as an event, ' \
                                                                        "or not declared once at its line's head"
  end

  it "a quiet morning's window is the 24 hours, on the hour, from six" do
    skip solver
  end

  it "tomorrow morning lands at tomorrow's time, and tomorrow night is not drawn" do
    by = on(quiet_rows)['events'].to_h { [it['title'], it] }

    expect([by['Dentist']&.fetch('start_min'), by['Early Flight']&.fetch('start_min'), by.key?('Book Club')])
      .to eq([14 * 60, day + (5 * 60), true]),
          "tomorrow's 05:00 has to be 05:00 of the second day, and a 19:00 event is sent rather than withheld"
  end

  it 'the window opens where the step puts it, and counts what fell off the front' do
    skip solver
  end

  it 'a setting the board no longer reads still draws a board' do
    at = '2026-09-09T21:00:00Z'
    rows = [['20260910', '1400', '1500', 'Dentist'], ['20260911', '0900', '1000', 'Sprint Review']]
    shape = ->(data) { [titles(data).sort, data['title_word'], data['days'].size] }
    plain = shape.(on(rows, at:))
    stale = [{ show_day: 'auto' }, { show_day: 'tomorrow' }, { rolling_view: 'one' },
             { show_day: 'auto', switch_hour: '18', rolling_view: 'one' }]

    expect(stale.to_h { [it, shape.(on(rows, at:, **it))] }).to eq(stale.to_h { [it, plain] }),
                                                                 'a stale setting drew a different board'
  end

  it 'a day the board is not drawing leaves the board as it found it' do
    cfg = JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Ada' },
                                    { url: 'https://example.com/b.ics', name: 'Bo' }])
    data = board(now:, fields: { config_json: cfg, show_day: 'tomorrow' },
                 mocks: { Metro::FORECAST => '{}',
                          'https://example.com/b.ics' => feed([['20260911', '1000', '1100', 'Bo Only']]),
                          '*' => feed([['20260909', '1400', '1500', 'Dentist'], ['20260910', '0900', '0915', 'Standup'],
                                       ['20260910', '1100', '1200', 'Workshop'], ['20260910', '1400', '1500', 'Dentist']]) })

    expect(data['legend'].map { it['name'] }).to eq(['Ada']),
                                                 'a line that exists only on a day the board is not drawing got a rail'
  end

  it 'the board changes shape only at the steps, on the hour, and never gives tomorrow back' do
    skip solver
  end

  it 'the evening board has tomorrow and tonight, and the morning has rolled off' do
    skip solver
  end

  it 'a rolling board carries no sunrise and no sunset' do
    expect(on(quiet_rows)['weather'].reject { it['type'] == 'weather' }).to eq([]),
                                                                            'a rolling board put sky markers back on'
  end
end
