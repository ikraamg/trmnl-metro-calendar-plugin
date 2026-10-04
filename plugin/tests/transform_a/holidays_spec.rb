# frozen_string_literal: true

require_relative '../support/transform_a'

# Ported from test/trmnl/transform/holidays.spec.js.
RSpec.describe 'holidays' do
  include TransformA::Helpers

  let(:now) { '2026-12-25T09:00:00Z' } # Christmas Day, a Friday
  let(:christmas) { [{ start: '20261225', end: '20261226', summary: 'Christmas Day' }] }
  let(:ada_rule_calendar) do
    { url: 'https://example.com/ada.ics', name: 'Ada', rules: [{ match: { type: 'any' }, line: 'Ada' }] }
  end

  # The everyday setup: a line per person, plus a subscribed holiday feed that names nobody.
  def config(over = {})
    { lines: [{ name: 'Ada' }, { name: 'Bo' }],
      calendars: [ada_rule_calendar, { url: 'https://example.com/hol.ics', holiday: true }] }.merge(over)
  end

  def config_fields(json) = TransformA.fields(config_json: JSON.generate(json))

  # The holiday feed answers; Ada's own calendar answers empty.
  def serve(text) = { %r{/ada\.ics} => Metro.ics([]), '*' => text }

  def board(text, json, at: now)
    run_transform(now: at, fields: config_fields(json), mocks: serve(text)).data['data']
  end

  def holiday_titles(payload) = TransformA.titles(payload['holidays'])

  # ---------------------------------------------------------------- whose

  it 'a holiday belongs to the day, not to anybody' do
    payload = board(TransformA.all_day_ics(christmas, 'Holidays in Belgium'), config)

    expect(holiday_titles(payload)).to eq(['Christmas Day']), 'the day is not named'
    expect(payload['all_day']).to eq([]), "a holiday was declared at a line's head: it is nobody's state"
  end

  # ---------------------------------------------------------- whose, exactly

  it 'a holiday a rule gives to somebody goes to their head, not the header' do
    payload = board(TransformA.all_day_ics([{ start: '20261225', end: '20261226', summary: 'Half Term' }]), config(
      calendars: [ada_rule_calendar,
                  { url: 'https://example.com/hol.ics', holiday: true,
                    rules: [{ match: { type: 'contains', value: 'Half Term' }, line: 'Bo' }] }]
    ))
    bo = payload['legend'].find { it['name'] == 'Bo' }

    expect(payload['holidays']).to eq([]), "a holiday somebody owns is not the day's"
    expect(TransformA.titles(payload['all_day'])).to eq(['Half Term']), 'it should be at a head'
    expect(bo).not_to be_nil, 'Bo got no line, so the holiday had nowhere to be declared'
    expect(payload['all_day'][0]['owners']).to eq([bo['key']]), 'declared against the wrong line'
    expect(TransformA.event_items(payload)).to eq([]), 'and still nothing on the axis'
  end

  it 'two lines sharing one are one origin, named once' do
    payload = board(TransformA.all_day_ics([{ start: '20261225', end: '20261226', summary: 'Half Term' }]), config(
      lines: [{ name: 'Ada' }, { name: 'Bo' }, { name: 'Cy' }],
      calendars: [ada_rule_calendar,
                  { url: 'https://example.com/hol.ics', holiday: true,
                    rules: [{ match: { type: 'contains', value: 'Half Term' }, line: %w[Bo Cy] }] }]
    ))

    expect(payload['all_day'].length).to eq(1), 'two children are not on two holidays'
    expect(payload['all_day'][0]['owners'].length).to eq(2), 'both should own it'
    expect(payload['holidays']).to eq([]), "and it is not also the day's"
  end

  it 'the fallback chain is never consulted for a holiday' do
    payload = board(TransformA.all_day_ics(christmas), config(
      calendars: [ada_rule_calendar,
                  { url: 'https://example.com/hol.ics', name: 'Holidays in Belgium', holiday: true }]
    ))
    names = payload['legend'].map { it['name'] }

    expect(holiday_titles(payload)).to eq(['Christmas Day']), "it is the day's"
    expect(payload['all_day']).to eq([]), "and nobody's"
    expect(names).not_to(include(/Holiday/i), "the feed's own name became a line: #{names}")
  end

  # ------------------------------------------------- the plain list of links

  it 'a plain list can mark a holiday feed, with no JSON at all' do
    fields = TransformA.fields(config_json: "https://example.com/ada.ics\nhttps://example.com/hol.ics holiday\n")
    payload = run_transform(now:, fields:,
                            mocks: serve(TransformA.all_day_ics(christmas, 'Holidays in Belgium'))).data['data']
    names = payload['legend'].map { it['name'] }

    expect(holiday_titles(payload)).to eq(['Christmas Day']), 'the marked feed did not reach the day'
    expect(names).not_to(include(/Holiday/i), "it still became a line: #{names}")
  end

  it 'the marker is the whole word at the end, not a substring of a link' do
    fields = TransformA.fields(config_json: "https://example.com/hol.ics?type=holiday\n")
    payload = run_transform(now:, fields:,
                            mocks: serve(TransformA.all_day_ics(christmas, 'Holidays in Belgium'))).data['data']

    expect(payload['holidays']).to eq([]), 'a url containing the word was read as a marker'
  end

  it 'a holiday feed puts no line on the board' do
    payload = board(TransformA.all_day_ics(christmas, 'Holidays in Belgium'), config(
      calendars: [ada_rule_calendar,
                  { url: 'https://example.com/hol.ics', name: 'Holidays in Belgium', holiday: true }]
    ))
    names = (payload['legend'] || []).map { it['name'] }

    expect(names).not_to include('Holidays in Belgium'), "the holiday feed became a line: #{names.join(', ')}"
  end

  it 'without holiday:true it still lands on a line, which is the shape being fixed' do
    payload = board(TransformA.all_day_ics([{ start: '20261225', end: '20261226', summary: 'Ada on leave' }]),
                    { lines: [{ name: 'Ada' }], calendars: [{ url: 'https://example.com/a.ics', name: 'Ada' }] })

    expect(TransformA.titles(payload['all_day'])).to eq(['Ada on leave']),
                                                     "an ordinary all-day event stopped being declared at its line's head"
    expect(payload['holidays']).to eq([]), "and it is not the day's"
  end

  it 'a rule can say it per event, for a feed that carries both kinds' do
    feed = TransformA.all_day_ics([{ start: '20261225', end: '20261226', summary: 'Christmas Day' },
                                   { start: '20261225', end: '20261226', summary: 'Ada on leave' }])
    payload = board(feed, { lines: [{ name: 'Ada' }],
                            calendars: [{ url: 'https://example.com/a.ics', name: 'Ada',
                                          rules: [{ match: { type: 'contains', value: 'Christmas' },
                                                    holiday: true }] }] })

    expect(holiday_titles(payload)).to eq(['Christmas Day'])
    expect(TransformA.titles(payload['all_day'])).to eq(['Ada on leave']), 'the rule took the wrong entry, or took both'
  end

  it 'a holiday written as a timed block is still a holiday' do
    feed = Metro.ics([{ start: '20261225T000000', end: '20261225T235900', summary: 'Christmas Day' }])
    payload = board(feed, { lines: [{ name: 'Ada' }], calendars: [{ url: 'https://example.com/h.ics', holiday: true }] })

    expect(holiday_titles(payload)).to eq(['Christmas Day'])
    expect(TransformA.event_items(payload).length).to eq(0),
                                                      'a holiday reached the hour scale, which is the one place it cannot be'
  end

  it 'the same holiday from two feeds is named once' do
    payload = board(TransformA.all_day_ics(christmas),
                    { lines: [{ name: 'Ada' }],
                      calendars: [{ url: 'https://example.com/h1.ics', holiday: true },
                                  { url: 'https://example.com/h2.ics', holiday: true }] })

    expect(holiday_titles(payload)).to eq(['Christmas Day'])
  end

  it 'a day full of observances is still one day' do
    feed = TransformA.all_day_ics(['Christmas Day', 'School Holiday', 'Feast of the Nativity', 'Quarter Day'].map do
      { start: '20261225', end: '20261226', summary: it }
    end)

    expect(holiday_titles(board(feed, config))).to eq(['Christmas Day'])
  end

  # ------------------------------------------------------------ recurrence

  it 'a yearly recurrence is seen on its anniversary' do
    feed = TransformA.all_day_ics([{ start: '20200101', end: '20200102', rrule: 'FREQ=YEARLY',
                                     summary: "New Year's Day" }])

    expect(holiday_titles(board(feed, config, at: '2027-01-01T09:00:00Z'))).to eq(["New Year's Day"]),
                                                                              'a yearly holiday seven years after its DTSTART was dropped'
  end

  it 'a yearly recurrence is not seen on every other day of the year' do
    feed = TransformA.all_day_ics([{ start: '20200101', end: '20200102', rrule: 'FREQ=YEARLY',
                                     summary: "New Year's Day" }])

    expect(board(feed, config)['holidays']).to eq([]), "Christmas Day is not New Year's Day"
  end

  it 'an ordinal BYDAY finds the moving date, not the anniversary' do
    feed = TransformA.all_day_ics([{ start: '20261126', end: '20261127', rrule: 'FREQ=YEARLY;BYDAY=4TH;BYMONTH=11',
                                     summary: 'Thanksgiving' }])

    expect(holiday_titles(board(feed, config, at: '2027-11-25T09:00:00Z'))).to eq(['Thanksgiving']),
                                                                              'the fourth Thursday of 2027 was missed'
    expect(holiday_titles(board(feed, config, at: '2027-11-26T09:00:00Z'))).not_to include('Thanksgiving'),
                                                                                  'the anniversary of the start date was taken for the holiday'
  end

  it 'a dated entry per year, which is what Google writes, needs no recurrence at all' do
    feed = TransformA.all_day_ics(%w[2025 2026 2027].map do
      { start: "#{it}1225", end: "#{it}1226", summary: 'Christmas Day' }
    end)

    expect(holiday_titles(board(feed, config))).to eq(['Christmas Day']),
                                                   'the one whose date is today should be the one that shows'
  end

  # ----------------------------------------------------------------- ranges

  it 'a range says which day of it the board is drawing' do
    feed = TransformA.all_day_ics([{ start: '20270405', end: '20270410', summary: 'Spring Break' }])
    on = lambda do |iso|
      holiday = (board(feed, config, at: iso)['holidays'] || [])[0]
      holiday && holiday.values_at('day_index', 'day_span', 'day_label')
    end

    expect(on.call('2027-04-05T09:00:00Z')).to eq([0, 5, 'Day 1 of 5']), 'the first day of the range'
    expect(on.call('2027-04-07T09:00:00Z')).to eq([2, 5, 'Day 3 of 5']),
                                               'a day INSIDE the range has to read differently from its first day'
    expect(on.call('2027-04-09T09:00:00Z')).to eq([4, 5, 'Day 5 of 5'])
  end

  it 'the day after a range ends says nothing' do
    feed = TransformA.all_day_ics([{ start: '20270405', end: '20270410', summary: 'Spring Break' }])

    expect(board(feed, config, at: '2027-04-10T09:00:00Z')['holidays']).to eq([])
  end

  it 'a single day carries no ordinal to state' do
    holiday = board(TransformA.all_day_ics(christmas), config)['holidays'][0]

    expect(holiday['day_span']).to eq(1)
    expect(holiday['day_label']).to be_nil, '"Day 1 of 1" is a sentence about nothing, and header width is board'
  end

  it 'the ordinal is translated, not assembled on the client' do
    feed = TransformA.all_day_ics([{ start: '20270405', end: '20270410', summary: 'Spring Break' }])
    run = run_transform(now: '2027-04-07T09:00:00Z', fields: config_fields(config), locale: 'nl-BE',
                        mocks: { Metro::I18N => { json: { holiday_day: 'Dag {n} van {m}' } }, '*' => feed })

    expect(run.data.dig('data', 'holidays', 0, 'day_label')).to eq('Dag 3 van 5')
  end

  # -------------------------------------------------------------- which day

  it "a holiday tomorrow is tomorrow's, and says so" do
    holidays = board(TransformA.all_day_ics([{ start: '20261226', end: '20261227', summary: 'Boxing Day' }]),
                     config)['holidays'] || []

    expect(TransformA.titles(holidays.select { (it['day'] || 0).zero? })).to eq([]),
                                                                           "tomorrow's holiday was stated on today's board"
    expect(holidays.map { it.values_at('title', 'day') }).to eq([['Boxing Day', 1]]),
                                                            "tomorrow's holiday should travel with tomorrow"
  end

  it 'a range that started before the board still says where it is in it' do
    feed = TransformA.all_day_ics([{ start: '20270329', end: '20270412', summary: 'Half Term' }])
    holiday = board(feed, config, at: '2027-04-08T09:00:00Z')['holidays'][0]

    expect(holiday.values_at('day_index', 'day_span')).to eq([10, 14])
    expect(holiday['day_label']).to eq('Day 11 of 14')
  end

  # ------------------------------------------------------------- it is free

  it 'a holiday costs the board no line and no depth' do
    json = config(lines: [{ name: 'Ada', hideWhenEmpty: true }, { name: 'Bo', hideWhenEmpty: true }])
    run = run_transform(now:, fields: config_fields(json),
                        mocks: { %r{/hol\.ics} => TransformA.all_day_ics(christmas), '*' => Metro.ics([]) })
    payload = run.data['data']

    expect(payload['legend']).to eq([]), 'a holiday put a line on an empty board'
    expect(holiday_titles(payload)).to eq(['Christmas Day']), 'and it is still stated'
  end
end
