# frozen_string_literal: true

require_relative '../support/transform_b'

# Ported from test/trmnl/transform/one-event.spec.js.
RSpec.describe 'one-event' do
  include TransformBHelpers

  solver = 'stays in the Node runner: asserts line order through the solver (arranged, solver/order.js)'
  same = %w[20260907T140000Z 20260907T150000Z]
  long = %w[20260907T083000Z 20260907T150000Z]

  let(:now) { '2026-09-07T12:00:00Z' } # a Monday
  let(:two_lines) do
    { lines: [{ name: 'Ada' }, { name: 'Bo' }],
      calendars: [{ url: 'https://example.com/a.ics', rules: [{ match: { type: 'any' }, line: 'Ada' }] },
                  { url: 'https://example.com/b.ics', rules: [{ match: { type: 'any' }, line: 'Bo' }] }] }
  end

  # two calendars, each naming the same meeting for a different person
  def two_feeds(summary, time_a, time_b)
    { 'https://example.com/a.ics' => TransformB.ics([{ start: time_a[0], end: time_a[1], summary: }]),
      'https://example.com/b.ics' => TransformB.ics([{ start: time_b[0], end: time_b[1], summary: }]) }
  end

  def titled(data, title) = data['events'].select { it['title'] == title }

  it 'the same event on two calendars becomes one event on both lines' do
    swims = titled(board(now:, fields: config(two_lines), mocks: two_feeds('Swim Class', same, same)), 'Swim Class')

    expect(swims.map { (it['co_owners'] || []).size }).to eq([1]),
                                                          'one swim class, the second line a co-owner, not a second event'
  end

  it 'two events with the same title at DIFFERENT times stay two events' do
    data = board(now:, fields: config(two_lines),
                 mocks: two_feeds('Swim Class', same, %w[20260907T160000Z 20260907T170000Z]))

    expect(titled(data, 'Swim Class').size).to eq(2), "two o'clock and four o'clock are not the same lesson"
  end

  it 'the same long event on two calendars is one event with a co-owner' do
    school = titled(board(now:, fields: config(two_lines), mocks: two_feeds('School Day', long, long)), 'School Day')

    expect(school.map { [it['co_owners'].size, it['co_owners'].first != it['owner'], it['start_min'], it['end_min']] })
      .to eq([[1, true, (8 * 60) + 30, 15 * 60]]), 'one school day on both lines, keeping the hours it ran'
  end

  it 'lines that share an event are laid out next to each other' do
    skip solver
  end

  it 'the order is the one that crosses least, not the one greed reaches first' do
    skip solver
  end

  it 'the day stretches to fit what is on it, with room after the last event' do
    data = board(now: '2026-09-07T05:00:00Z',
                 fields: config(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }]),
                 mocks: { 'https://example.com/a.ics' => TransformB.ics([
                   { start: '20260907T043000Z', end: '20260907T053000Z', summary: 'Early Shift' },
                   { start: '20260907T200000Z', end: '20260907T203000Z', summary: 'Late Call' },
                   { start: '20260907T120000Z', end: '20260907T130000Z', summary: 'Midday' }
                 ]) })
    first = data['events'].map { it['start_min'] }.min
    last = data['events'].map { it['end_min'] }.max

    expect(data).to include('day_start_min' => (be <= first).and(be >= 0),
                            'day_end_min' => (be >= last + 60).and(be <= 48 * 60))
  end
end
