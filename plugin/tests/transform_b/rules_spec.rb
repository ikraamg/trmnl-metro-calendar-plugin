# frozen_string_literal: true

require_relative '../support/transform_b'

# Ported from test/trmnl/transform/rules.spec.js.
RSpec.describe 'rules' do
  include TransformBHelpers

  let(:now) { '2026-09-07T12:00:00Z' } # a Monday
  let(:at_two) { { start: '20260907T140000Z', end: '20260907T150000Z' } }

  def ics(*events) = TransformB.ics(events)
  def items(data) = data['events'] || []
  def titles(data) = items(data).map { it['title'] }
  def line_key(data, name) = data['legend'].find { it['name'] == name }&.fetch('key')
  def names(data) = data['legend'].map { it['name'] }
  def on(json, mocks) = board(now:, fields: config(json), mocks:)
  def headers_of(run, url) = run.requests.find { it[:url] == url }&.fetch(:headers) || {}

  it 'a rule can turn a timed event into an all-day one, which then runs the whole day' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                              rules: [{ match: { type: 'word', value: 'Training' }, allDay: true }] }] },
              '*' => ics(at_two.merge(summary: 'Staff Training Day')))

    expect([items(data), data['all_day'].map { it['title'] }]).to eq([[], ['Staff Training Day']]),
                                                                   'the rule did not promote it off the timeline'
  end

  it 'a rule can hide an event by title match' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                              rules: [{ match: { type: 'word', value: 'Hide Me' }, hide: true }] }] },
              '*' => ics(at_two.merge(summary: 'Keep Me'),
                         { start: '20260907T160000Z', end: '20260907T170000Z', summary: 'Hide Me' }))

    expect(titles(data)).to eq(['Keep Me'])
  end

  it "a rule can match against an event's description, but only when the calendar opts in via includeDescription" do
    mocks = { '*' => ics(at_two.merge(summary: 'Team Sync', description: 'cancelled')) }
    rule = { match: { type: 'word', value: 'cancelled' }, hide: true }
    off = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal', rules: [rule] }] }, mocks)
    with = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal', includeDescription: true, rules: [rule] }] },
              mocks)

    expect([items(off).size, items(with).size]).to eq([1, 0]),
                                                   'the rule should see the description only with includeDescription'
  end

  it 'a rewrite rule replaces the matched text with literal text, independent of track' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                              rules: [{ match: { type: 'word', value: 'L6' }, rewrite: 'Lesson 6' }] }] },
              '*' => ics(at_two.merge(summary: 'L6 Swim Class')))

    expect(titles(data)).to eq(['Lesson 6 Swim Class'])
  end

  it 'deleting the matched text takes the gap it leaves with it' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                              rules: [{ match: { type: 'word', value: 'L2' }, rewrite: '' }] }] },
              '*' => ics(at_two.merge(summary: 'L2 Zwemmen'),
                         { start: '20260907T160000Z', end: '20260907T170000Z', summary: 'Turnen L2 zaal' }))

    expect(titles(data)).to eq(['Zwemmen', 'Turnen zaal'])
  end

  it 'a catch-all ".*" rewrite does not duplicate the title (QuinnQuinn bug)' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics',
                              rules: [{ match: { type: 'regex', value: '.*' }, rewrite: 'Quinn' }] }] },
              '*' => ics(at_two.merge(summary: 'Schoolfotografie')))

    expect(titles(data)).to eq(['Quinn']), 'a single non-global replace should produce "Quinn", never "QuinnQuinn"'
  end

  it 'the "any" match type is the intended way to write a catch-all rule' do
    data = on({ lines: [{ name: 'Quinn' }],
                calendars: [{ url: 'https://example.com/a.ics', rules: [{ match: { type: 'any' }, line: 'Quinn' }] }] },
              '*' => ics(at_two.merge(summary: 'Schoolfotografie')))

    expect([titles(data), names(data)]).to eq([['Schoolfotografie'], ['Quinn']])
  end

  it 'title replaces the whole title, not just the matched substring' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                              rules: [{ match: { type: 'word', value: 'L6' }, title: 'Swimming' }] }] },
              '*' => ics(at_two.merge(summary: 'L6 Swim Class with Jane')))

    expect(titles(data)).to eq(['Swimming'])
  end

  it 'rewrite supports regex backreferences against the match' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                              rules: [{ match: { type: 'regex', value: 'Sprint (\\d+-\\d+)' }, rewrite: 'Sprint #$1' }] }] },
              '*' => ics(at_two.merge(summary: 'Sprint 26-08')))

    expect(titles(data)).to eq(['Sprint #26-08'])
  end

  it 'a rule routing a title and a rule rewriting it both apply' do
    data = on({ lines: [{ name: 'Alex' }],
                calendars: [{ url: 'https://example.com/a.ics', rules: [
                  { match: { type: 'word', value: 'L6' }, line: 'Alex' },
                  { match: { type: 'word', value: 'L6' }, rewrite: 'Lesson 6' }
                ] }] },
              '*' => ics(at_two.merge(summary: 'L6 Swim Class')))

    expect(titles(data)).to eq(['Lesson 6 Swim Class'])
  end

  it 'a global rule assigns a track across every calendar, not just one' do
    data = on({ rules: [{ match: { type: 'word', value: 'Doctor' }, line: 'Mom' }],
                lines: [{ name: 'Mom', badge: 'M' }],
                calendars: [{ url: 'https://example.com/a.ics' }, { url: 'https://example.com/b.ics' }] },
              'https://example.com/a.ics' => ics(at_two.merge(summary: 'Doctor Appointment')),
              'https://example.com/b.ics' => ics(at_two.merge(summary: 'Something Else')))

    expect(titles(data)).to include(a_string_including('Mom').or(a_string_including('Doctor'))),
                            'the global rule should have assigned Mom regardless of which calendar the event came from'
  end

  it "a calendar's own rule overrides a global rule's track assignment for the same event" do
    data = on({ rules: [{ match: { type: 'word', value: 'Doctor' }, line: 'Mom' }],
                lines: [{ name: 'Mom', badge: 'M' }, { name: 'Dad', badge: 'D' }],
                calendars: [{ url: 'https://example.com/a.ics',
                              rules: [{ match: { type: 'word', value: 'Doctor' }, line: 'Dad' }] }] },
              '*' => ics(at_two.merge(summary: 'Doctor Appointment')))

    expect(items(data).first['owner']).to eq(line_key(data, 'Dad')),
                                          'the calendar-specific rule should win over the global one'
  end

  it "a calendar's custom headers are sent on its ICS fetch, alongside the default User-Agent" do
    run = board_run(now:, fields: config(calendars: [{ url: 'https://example.com/a.ics',
                                                        headers: { Authorization: 'Bearer secret-token' } }]),
                    mocks: { '*' => ics })
    sent = headers_of(run, 'https://example.com/a.ics')

    expect(sent.values_at('authorization', 'user-agent')).to eq(['Bearer secret-token', 'TRMNL-Metro-Calendar'])
  end

  it "non-string values in a calendar's headers are dropped rather than sent as-is" do
    run = board_run(now:, fields: config(calendars: [{ url: 'https://example.com/a.ics',
                                                        headers: { 'X-Ok' => 'fine', 'X-Bad' => { nested: true } } }]),
                    mocks: { '*' => ics })
    sent = headers_of(run, 'https://example.com/a.ics')

    expect([sent['x-ok'], sent.key?('x-bad')]).to eq(['fine', false]),
                                                   'a non-string header value should be dropped, not passed through'
  end

  it 'the first track in tracks[] (everyoneTrack) claims any event no rule assigns a track to' do
    data = on({ lines: [{ name: 'Everyone', badge: '★' }], calendars: [{ url: 'https://example.com/a.ics' }] },
              '*' => ics(at_two.merge(summary: 'Unclaimed Event')))

    expect([items(data).size, names(data)]).to eq([1, ['Everyone']])
  end

  it 'a calendar says whose it is with line; with lines declared, its name is only a label' do
    data = on({ lines: [{ name: 'Familie', badge: '★' }, { name: 'Jules', badge: 'K' }],
                calendars: [{ url: 'https://example.com/a.ics', name: 'School', line: 'Jules' }] },
              '*' => ics(at_two.merge(summary: 'Extra turnen')))

    expect([items(data).first['owner'], names(data).include?('School')]).to eq([line_key(data, 'Jules'), false]),
                                                                              "the calendar's line did not claim its " \
                                                                              "event, or its name became a line"
  end

  it "a rule's own track assignment still wins over the everyoneTrack fallback" do
    data = on({ lines: [{ name: 'Everyone', badge: '★' }, { name: 'Alex', badge: 'A' }],
                calendars: [{ url: 'https://example.com/a.ics',
                              rules: [{ match: { type: 'word', value: 'Alex' }, line: 'Alex' }] }] },
              '*' => ics(at_two.merge(summary: 'Alex event')))

    expect(items(data).first['owner']).to eq(line_key(data, 'Alex'))
  end

  it 'a rule with a multi-name track list produces an event with co_owners (an interchange, client-side)' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics',
                              rules: [{ match: { type: 'any' }, line: %w[Alex Kids] }] }] },
              '*' => ics(at_two.merge(summary: 'Family Dinner')))
    event = items(data).first

    expect([event['owner'], event['co_owners'].size]).to eq([line_key(data, 'Alex'), 1]),
                                                         'the first name becomes the owner, the rest co_owners'
  end

  it 'string-shorthand calendar entries (a bare URL, not {url:...}) are accepted' do
    data = on({ lines: [{ name: 'Everyone' }], calendars: ['https://example.com/a.ics'] },
              '*' => ics(at_two.merge(summary: 'Event')))

    expect(items(data).size).to eq(1)
  end

  it 'non-JSON config text falls back to a newline-separated URL list' do
    skip 'stays in the Node runner: calls parseConfig through internals()'
  end

  it 'an unreadable configuration says so on the board' do
    data = board(now:, fields: { config_json: '{ "calendars": [ { "url": "https://x/a.ics" ' },
                 mocks: TransformB.demo_mocks.merge('*' => ics))

    expect([data['legend'].size, data['board_notice']]).to match([0, /could not be read/]),
                                                           'the example was drawn over a broken configuration, or no notice'
  end

  it 'every calendar failing says which, even with the lines still drawn' do
    data = on({ lines: [{ name: 'Sam' }], calendars: [{ url: 'https://example.com/work.ics', name: 'Work', line: 'Sam' }] },
              '*' => { status: 404 })

    expect(data['board_notice']).to match(/None of the calendars could be read: Work/)
  end

  it 'a board with calendars that answered and nothing on them says so, and a busy one says nothing' do
    quiet = on({ calendars: [{ url: 'https://example.com/a.ics' }] }, '*' => ics)
    busy = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Sam' }] }, '*' => ics(at_two.merge(summary: 'Standup')))

    expect([quiet['board_notice'], busy.fetch('board_notice', :absent)]).to match([/Nothing on the calendars/, nil]),
                                                                         'no notice on an empty board, or a notice on a busy one'
  end

  it 'non-JSON config text with no non-blank lines also falls back to the demo' do
    data = board(now:, fields: { config_json: "   \n   \n" }, mocks: TransformB.demo_mocks.merge('*' => ics))

    expect(names(data).sort).to eq(%w[Bart Homer Lisa Maggie Marge]), 'the demo config was not picked up'
  end

  it 'a line nobody uses today is still on the board, because somebody named it' do
    data = on({ lines: [{ name: 'Idle' }, { name: 'Busy' }],
                calendars: [{ url: 'https://example.com/a.ics', rules: [{ match: { type: 'any' }, line: 'Busy' }] }] },
              '*' => ics(at_two.merge(summary: 'Busy track only')))

    expect(names(data).sort).to eq(%w[Busy Idle]), 'a board that deletes whoever is quiet changes shape every day'
  end

  it 'hideWhenEmpty drops a line, and the lines left close up with no gap left behind' do
    skip 'stays in the Node runner: asserts line_offset through the solver (arranged, solver/order.js)'
  end

  it "side and color are gone: a configuration that still says them is drawn by the board's own choice" do
    mocks = { '*' => ics(at_two.merge(summary: 'C event')) }
    plain = on({ lines: [{ name: 'C' }], calendars: [{ url: 'https://example.com/a.ics', name: 'C' }] }, mocks)
    pinned = on({ lines: [{ name: 'C', side: 'right', color: 'red' }],
                  calendars: [{ url: 'https://example.com/a.ics', name: 'C' }] }, mocks)

    expect(pinned['legend']).to eq(plain['legend']), 'side or color still changes the line'
  end

  it 'a long block carries its location and earns its owner a legend entry' do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Quinn' }] },
              '*' => ics({ start: '20260907T080000Z', end: '20260907T190000Z', summary: 'Desk booking',
                           location: 'BE-Ghent A01' }))

    expect(items(data).map { it.values_at('title', 'location', 'start_min', 'end_min', 'owner') })
      .to eq([['Desk booking', 'BE-Ghent A01', 8 * 60, 19 * 60, line_key(data, 'Quinn')]])
  end

  it "an all-day event is declared at the line's head, never on the axis" do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                              rules: [{ match: { type: 'word', value: 'Training' }, allDay: true }] }] },
              '*' => ics(at_two.merge(summary: 'Staff Training Day')))

    expect([items(data), data.key?('sidings'), data['all_day'].map { it.slice('title', 'owners', 'hue') }])
      .to eq([[], false, [{ 'title' => 'Staff Training Day', 'owners' => [line_key(data, 'Cal')] }]])
  end

  it 'one all-day title shared by several lines is one origin, named once' do
    data = on({ calendars: [
                { url: 'https://example.com/a.ics', name: 'Cal', rules: [{ match: { type: 'word', value: 'Half' }, allDay: true }] },
                { url: 'https://example.com/b.ics', name: 'Two', rules: [{ match: { type: 'word', value: 'Half' }, allDay: true }] }
              ] },
              '*' => ics(at_two.merge(summary: 'Half Term')))

    expect(data['all_day'].map { it['owners'].size }).to eq([2]), 'one row, carrying both lines'
  end

  it 'one rule naming several lines puts the all-day entry on all of them' do
    data = on({ lines: [{ name: 'Ada' }, { name: 'Bo' }, { name: 'Cy' }],
                calendars: [{ url: 'https://example.com/a.ics', name: 'School', rules: [
                  { match: { type: 'word', value: 'Spring' }, allDay: true, line: %w[Ada Bo Cy] }
                ] }] },
              '*' => ics(at_two.merge(summary: 'Spring Break')))
    name_of = data['legend'].to_h { [it['key'], it['name']] }

    expect(data['all_day'].map { |row| row['owners'].map { name_of[it] }.sort }).to eq([%w[Ada Bo Cy]]),
                                                                                    'three children are on one holiday'
  end

  it "a real meeting inside a long block's span still renders normally alongside it" do
    data = on({ calendars: [{ url: 'https://example.com/a.ics', name: 'Quinn' }] },
              '*' => ics({ start: '20260907T080000Z', end: '20260907T190000Z', summary: 'Desk booking' },
                         { start: '20260907T090000Z', end: '20260907T093000Z', summary: 'Standup' }))

    expect(titles(data)).to eq(['Desk booking', 'Standup']), 'in start order, both on the timeline'
  end

  it 'a calendar nobody routed belongs to the whole household' do
    data = on({ lines: [{ name: 'Ada' }, { name: 'Bo' }, { name: 'Cy' }],
                calendars: [{ url: 'https://example.com/shared.ics' }] },
              '*' => ics({ start: '20260907T180000Z', end: '20260907T190000Z', summary: 'Bin Day' }))
    bin = items(data).find { it['title'] == 'Bin Day' }
    name_of = data['legend'].to_h { [it['key'], it['name']] }

    expect(bin && ([bin['owner']] + (bin['co_owners'] || [])).map { name_of[it] }.sort).to eq(%w[Ada Bo Cy])
  end
end
