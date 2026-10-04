# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/recurrence-override.spec.js.
RSpec.describe 'recurrence-override' do
  include TransformC::Helpers

  let(:config) { JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }]) }

  def titles(now, events, no_weather: false)
    mocks = { '*' => TransformC.ics_with_events(events) }
    mocks = { Metro::FORECAST => { status: 500, body: '' } }.merge(mocks) if no_weather
    TransformC.events(run_transform(now:, fields: { use_demo_data: 'false', config_json: config }, mocks:))
  end

  it "a no-op RECURRENCE-ID override does not duplicate the master's own occurrence" do
    events = [
      { uid: 'series-1', start: '20260601T090000Z', end: '20260601T091500Z', rrule: 'FREQ=WEEKLY;BYDAY=MO', summary: 'Team Standup' },
      { uid: 'series-1', recurrence_id: '20260907T090000Z', start: '20260907T090000Z', end: '20260907T091500Z', summary: 'Team Standup' }
    ]

    expect(titles('2026-09-07T09:30:00Z', events).length)
      .to eq(1), "the override should replace the master's occurrence, not add a second \"Team Standup\""
  end

  it "a RECURRENCE-ID override that moves the occurrence still suppresses the master's original slot" do
    events = [
      { uid: 'series-2', start: '20260907T090000Z', end: '20260907T091500Z', rrule: 'FREQ=WEEKLY;BYDAY=MO', summary: 'Standup' },
      { uid: 'series-2', recurrence_id: '20260907T090000Z', start: '20260907T110000Z', end: '20260907T111500Z', summary: 'Standup (moved)' }
    ]

    expect(titles('2026-09-07T09:30:00Z', events).map { it['title'] })
      .to eq(['Standup (moved)']), 'the original 09:00 occurrence should be suppressed and only the moved override should show'
  end

  it "an override for a DIFFERENT date does not suppress today's own occurrence" do
    events = [
      { uid: 'series-3', start: '20260601T090000Z', end: '20260601T091500Z', rrule: 'FREQ=WEEKLY;BYDAY=MO', summary: 'Standup' },
      { uid: 'series-3', recurrence_id: '20260914T090000Z', start: '20260914T100000Z', end: '20260914T101500Z',
        summary: 'Standup (moved next week)' }
    ]

    expect(titles('2026-09-07T09:30:00Z', events).map { it['title'] })
      .to eq(['Standup']), "today's own occurrence is untouched by an override targeting a different date"
  end

  it 'a fortnightly meeting does not happen every week' do
    events = [{ start: '20260910T100000Z', end: '20260910T110000Z', summary: 'Sprint Review', rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=TH' }]

    expect(titles('2026-09-10T08:00:00Z', events, no_weather: true).map { it['title'] })
      .to include('Sprint Review'), 'the fortnightly meeting is missing from the week it is actually on'
    expect(titles('2026-09-17T08:00:00Z', events, no_weather: true).map { it['title'] })
      .not_to include('Sprint Review'), 'a fortnightly meeting was drawn on its off week'
  end

  it 'an occurrence taken out of a series is not drawn' do
    events = [{ start: '20260910T093000Z', end: '20260910T094500Z', summary: 'Standup', rrule: 'FREQ=WEEKLY;BYDAY=TH,FR',
                exdate: '20260911T093000Z' }]
    days = titles('2026-09-10T08:00:00Z', events, no_weather: true).select { it && it['title'] == 'Standup' }
                                                                   .map { it['start_min'].fdiv(1440).floor }

    expect(days).to include(0), "Thursday's standup is missing"
    expect(days).not_to include(1), "Friday's standup was drawn, and the calendar says it was taken out of the series"
  end
end
