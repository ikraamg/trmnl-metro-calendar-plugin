# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/matchers.spec.js: the three cases that run the transform. The other seventeen
# call parseConfig inside transform.js, so they stay in the Node runner.
RSpec.describe 'matchers' do
  include TransformC::Helpers

  def titles(now, events, config)
    run = run_transform(now:, fields: { config_json: JSON.generate(config) }, mocks: { '*' => TransformC.ics_with_events(events) })
    TransformC.events(run).map { it['title'] }
  end

  it 'a rule naming a line leaves the title alone, whatever it matched' do
    got = titles('2026-09-08T12:00:00Z', [{ start: '20260908T083000Z', end: '20260908T092000Z', summary: 'L6 - Zwemmen' }],
                 lines: [{ name: 'Alex' }],
                 calendars: [{ url: 'https://x/a.ics', rules: [{ match: { type: 'word', value: 'L6' }, line: 'Alex' }] }])

    expect(got).to eq(['L6 - Zwemmen']), 'routing renamed the title'
  end

  it 'a rule can hide events only on a specific weekday, end to end' do
    events = [{ uid: 1, start: '20260907T140000Z', end: '20260907T150000Z', rrule: 'FREQ=WEEKLY;BYDAY=MO,WE', summary: 'Weekly Sync' }]
    config = { calendars: [{ url: 'https://example.com/a.ics', name: 'Cal',
                             rules: [{ match: { type: 'weekday', value: 'MO' }, hide: true }] }] }

    expect(titles('2026-09-07T12:00:00Z', events, config).length).to eq(0), 'Monday occurrence should be hidden by the weekday rule'
    expect(titles('2026-09-09T12:00:00Z', events, config).length)
      .to eq(1), 'Wednesday occurrence should still show -- the rule only targets Monday'
  end

  it '"hide these class codes except two" works end to end with no regex (real-world config)' do
    events = [
      { uid: 1, start: '20260908T083000Z', end: '20260908T092000Z', summary: 'L1 - Extra turnen' },
      { uid: 2, start: '20260908T083000Z', end: '20260908T092000Z', summary: 'L5 - Extra turnen' },
      { uid: 3, start: '20260908T092000Z', end: '20260908T101000Z', summary: 'L6 - Extra turnen' },
      { uid: 4, start: '20260908T092000Z', end: '20260908T101000Z', summary: 'L2 - Extra turnen' },
      { uid: 5, start: '20260908T130000Z', end: '20260908T144000Z', summary: 'L4 - Zwemmen' },
      { uid: 6, start: '20260908T130000Z', end: '20260908T144000Z', summary: 'L1 - Zwemmen' }
    ]
    config = {
      lines: [{ name: 'Familie' }, { name: 'Jules' }, { name: 'Remy' }],
      calendars: [{
        url: 'https://example.com/familie.ics', name: 'Familie',
        rules: [
          { match: { type: 'and', matchers: [
            { type: 'or', matchers: %w[L1 L3 L4 L5 K1 K2 K3 Kleuter].map { { type: 'word', value: it } } },
            { type: 'not', matcher: { type: 'word', value: 'L2' } },
            { type: 'not', matcher: { type: 'word', value: 'L6' } }
          ] }, hide: true },
          { match: { type: 'word', value: 'L2' }, line: 'Jules' },
          { match: { type: 'word', value: 'L6' }, line: 'Remy' }
        ]
      }]
    }

    expect(titles('2026-09-08T12:00:00Z', events, config).sort)
      .to eq(['L2 - Extra turnen', 'L6 - Extra turnen']), 'only L2/L6 should survive the hide rule'
  end
end
