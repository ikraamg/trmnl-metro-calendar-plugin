# frozen_string_literal: true

require_relative '../support/transform_b'

# Ported from test/trmnl/transform/rule-fields.spec.js.
RSpec.describe 'rule-fields' do
  include TransformBHelpers

  let(:now) { '2026-09-09T09:00:00Z' } # a Wednesday
  let(:at_school) do
    TransformB.ics([{ start: '20260909T090000Z', end: '20260909T093000Z', summary: 'Assembly', location: 'Springfield Elementary' },
                    { start: '20260909T110000Z', end: '20260909T113000Z', summary: 'Budget call', location: 'Zoom' }])
  end
  let(:long_day) do
    TransformB.ics([{ start: '20260909T083000Z', end: '20260909T150000Z', summary: 'In the office' },
                    { start: '20260909T100000Z', end: '20260909T103000Z', summary: 'Standup' },
                    { start: '20260909T070000Z', end: '20260909T073000Z', summary: 'Gym' }])
  end

  def on(ics, json) = board(now:, fields: config(json), mocks: { Metro::FORECAST => '{}', '*' => ics })
  def items(data) = data['events'] || []

  def tracks_of(data)
    name_of = data['legend'].to_h { [it['key'], it['name']] }
    items(data).map { "#{it['title']}@#{name_of[it['owner']]}" }.sort
  end

  def calendar(rules, **extra) = { url: 'https://example.com/a.ics', name: 'Desk', rules: }.merge(extra)

  it 'a rule can route on where the event is, not what it is called' do
    data = on(at_school, lines: [{ name: 'Work' }, { name: 'Kids' }],
                         calendars: [calendar([{ match: { type: 'contains', value: 'Elementary', field: 'location' },
                                                 line: 'Kids' }], name: 'Work')])

    expect(tracks_of(data)).to eq(['Assembly@Kids', 'Budget call@Work'])
  end

  it 'matching on the place leaves the title alone' do
    data = on(at_school, calendars: [calendar([{ match: { type: 'contains', value: 'Elementary', field: 'location' },
                                                 line: 'Kids' }], name: 'Work')])

    expect(tracks_of(data)).to eq(['Assembly@Kids', 'Budget call@Work']),
                               'the rule has to have fired for this to be about renaming at all'
  end

  it 'a rule can read the categories a calendar sets' do
    ics = TransformB.ics([{ start: '20260909T090000Z', end: '20260909T093000Z', summary: 'Match', categories: 'Sport,Kids' },
                          { start: '20260909T110000Z', end: '20260909T113000Z', summary: 'Standup', categories: 'Work' }])
    data = on(ics, lines: [{ name: 'Desk' }, { name: 'Club' }],
                   calendars: [calendar([{ match: { type: 'exact', value: 'Sport', field: 'categories' }, line: 'Club' }])])

    expect(tracks_of(data)).to eq(['Match@Club', 'Standup@Desk'])
  end

  it 'a category is a whole value, and an escaped comma does not split one' do
    ics = TransformB.ics([{ start: '20260909T090000Z', end: '20260909T093000Z', summary: 'Trip',
                            categories: 'Kids\\, school,Sport' }])
    data = on(ics, lines: [{ name: 'Desk' }, { name: 'Club' }],
                   calendars: [calendar([{ match: { type: 'exact', value: 'Kids, school', field: 'categories' },
                                           line: 'Club' }])])

    expect(tracks_of(data)).to eq(['Trip@Club'])
  end

  it 'asking for the description by name is opting into it' do
    ics = TransformB.ics([{ start: '20260909T090000Z', end: '20260909T093000Z', summary: 'Block',
                            description: 'room 4, with the sitter' }])
    data = on(ics, lines: [{ name: 'Desk' }, { name: 'Home' }],
                   calendars: [calendar([{ match: { type: 'contains', value: 'sitter', field: 'description' },
                                           line: 'Home' }])])

    expect(tracks_of(data)).to eq(['Block@Home'])
  end

  it 'a field of "title" really means only the title' do
    ics = TransformB.ics([{ start: '20260909T090000Z', end: '20260909T093000Z', summary: 'Block', description: 'sitter' }])
    cfg = lambda do |field|
      matcher = { type: 'contains', value: 'sitter' }.merge(field ? { field: } : {})
      { lines: [{ name: 'Desk' }, { name: 'Home' }],
        calendars: [calendar([{ match: matcher, line: 'Home' }], includeDescription: true)] }
    end

    expect([tracks_of(on(ics, cfg.(nil))), tracks_of(on(ics, cfg.('title')))]).to eq([['Block@Home'], ['Block@Desk']]),
                                                                                    'no field reads the description; ' \
                                                                                    'field title does not'
  end

  it '"any" reads everything the event carries' do
    ics = TransformB.ics([{ start: '20260909T090000Z', end: '20260909T093000Z', summary: 'Pickup', location: 'Springfield Elementary' },
                          { start: '20260909T110000Z', end: '20260909T113000Z', summary: 'Elementary theory', categories: 'Work' }])
    data = on(ics, lines: [{ name: 'Desk' }, { name: 'Kids' }],
                   calendars: [calendar([{ match: { type: 'contains', value: 'Elementary', field: 'any' }, line: 'Kids' }])])

    expect(tracks_of(data)).to eq(['Elementary theory@Kids', 'Pickup@Kids'])
  end

  it 'an unknown field falls back to the default rather than matching nothing' do
    data = on(at_school, lines: [{ name: 'Desk' }, { name: 'Kids' }],
                         calendars: [calendar([{ match: { type: 'contains', value: 'Assembly', field: 'titel' },
                                                 line: 'Kids' }])])

    expect(tracks_of(data)).to include('Assembly@Kids')
  end

  it 'a long block travels as an ordinary event, not a payload of its own' do
    data = on(long_day, calendars: [{ url: 'https://example.com/a.ics', name: 'Alex' }])
    long = items(data).find { it['title'] == 'In the office' }

    expect([data.key?('sidings'), items(data).map { it['title'] }.sort, long.values_at('start_min', 'end_min', 'co_owners')])
      .to eq([false, ['Gym', 'In the office', 'Standup'], [510, 900, []]])
  end

  it 'duration takes a ceiling as well as a floor' do
    data = on(long_day, lines: [{ name: 'Alex' }, { name: 'Quick' }],
                        calendars: [calendar([{ match: { type: 'duration', max: 30 }, line: 'Quick' }], name: 'Alex')])

    expect(tracks_of(data)).to eq(['Gym@Quick', 'In the office@Alex', 'Standup@Quick'])
  end

  it 'a rule can ask when the day it belongs to starts' do
    data = on(long_day, lines: [{ name: 'Alex' }, { name: 'Early' }],
                        calendars: [calendar([{ match: { type: 'time', to: '08:30' }, line: 'Early' }], name: 'Alex')])

    expect(tracks_of(data)).to eq(['Gym@Early', 'In the office@Alex', 'Standup@Alex'])
  end

  it 'the shape matchers compose with the word ones' do
    data = on(long_day, calendars: [calendar([{ match: { type: 'and', matchers: [
      { type: 'duration', max: 60 },
      { type: 'not', matcher: { type: 'contains', value: 'Gym' } }
    ] }, hide: true }], name: 'Alex')])

    expect(items(data).map { it['title'] }.sort).to eq(['Gym', 'In the office']),
                                                     'Standup was short and unnamed, so it went; Gym was named, so it stayed'
  end

  it 'a duration or time matcher with nothing to compare is dropped, not always-true' do
    data = on(long_day, lines: [{ name: 'Alex' }, { name: 'Nowhere' }],
                        calendars: [calendar([{ match: { type: 'duration' }, line: 'Nowhere' },
                                              { match: { type: 'time' }, line: 'Nowhere' }], name: 'Alex')])

    expect(tracks_of(data)).to all(include('@Alex'))
  end
end
