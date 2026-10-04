# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/recurrence-rules.spec.js.
RSpec.describe 'recurrence-rules' do
  include TransformC::Helpers

  def fires(rrule, start = '20260901T090000', extra = {})
    event = { uid: 'r', start:, end: start.sub(/T\d{2}/, 'T10'), rrule:, summary: 'Series' }.merge(extra)
    config = JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }])
    run = run_transform(now: '2026-09-15T06:00:00Z', fields: { config_json: config },
                        mocks: { '*' => TransformC.ics_with_events([event]) }, time_zone: 'Europe/Brussels')
    series = TransformC.events(run).select { it['title'] == 'Series' }
    { today: series.any? { it['start_min'] >= 0 && it['start_min'] < 1440 }, tomorrow: series.any? { it['start_min'] >= 1440 } }
  end

  def yes(rrule, start, why, extra = {}) = expect(fires(rrule, start, extra)[:today]).to(be(true), "#{why} (#{rrule})")

  def no(rrule, start, why, extra = {}) = expect(fires(rrule, start, extra)[:today]).to(be(false), "#{why} (#{rrule})")

  it 'DAILY fires every day, and INTERVAL counts days from the start' do
    yes('FREQ=DAILY', '20260901T090000', 'a daily series is not on today')
    yes('FREQ=DAILY;INTERVAL=2', '20260901T090000', 'every other day, fourteen days on')
    no('FREQ=DAILY;INTERVAL=2', '20260902T090000', 'every other day, thirteen days on')
    no('FREQ=DAILY;BYDAY=MO,WE,FR', '20260901T090000', 'a weekday filter let a Tuesday through')
  end

  it 'COUNT ends a series: ten days from the 1st is over by the 15th, fifteen is not' do
    no('FREQ=DAILY;COUNT=10', '20260901T090000', 'a series that ran out on the 10th is still on the board')
    yes('FREQ=DAILY;COUNT=15', '20260901T090000', 'the fifteenth of fifteen was dropped')
    expect(fires('FREQ=DAILY;COUNT=15')[:tomorrow]).to be(false), 'the series carried on past its count into tomorrow'
    no('FREQ=WEEKLY;COUNT=2', '20260901T090000', 'a two-week course is on its third week')
    yes('FREQ=WEEKLY;COUNT=3', '20260901T090000', 'the third week of three was dropped')
    yes('FREQ=WEEKLY;BYDAY=MO,TU;COUNT=4', '20260907T090000', 'Monday and Tuesday for two weeks: today is the fourth')
    no('FREQ=WEEKLY;BYDAY=MO,TU;COUNT=3', '20260907T090000', 'three occurrences end on Monday the 14th')
  end

  it 'MONTHLY by ordinal weekday, by day of the month, from the end, and by position' do
    yes('FREQ=MONTHLY;BYDAY=3TU', '20260721T090000', 'the third Tuesday of September is the 15th')
    no('FREQ=MONTHLY;BYDAY=2TU', '20260714T090000', 'the second Tuesday is the 8th')
    yes('FREQ=MONTHLY;BYDAY=-3TU', '20260721T090000', 'counted from the end, the 15th is the third last Tuesday')
    yes('FREQ=MONTHLY;BYMONTHDAY=15', '20260115T090000', 'the 15th of every month')
    yes('FREQ=MONTHLY;BYMONTHDAY=-16', '20260115T090000', 'sixteenth from the end of a 30-day month')
    yes('FREQ=MONTHLY', '20260615T090000', "a plain monthly repeats the start's day")
    no('FREQ=MONTHLY;INTERVAL=2', '20260815T090000', 'every other month skipped nothing')
    yes('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=11', '20260801T090000', 'the eleventh weekday of September is the 15th')
    no('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1', '20260801T090000', 'the last weekday is the 30th')
  end

  it 'YEARLY works for a timed entry too, and BYMONTH with an ordinal finds the moving date' do
    yes('FREQ=YEARLY', '20200915T180000', 'a timed yearly entry is not on its anniversary')
    no('FREQ=YEARLY', '20200916T180000', 'a yearly entry fired a day early')
    yes('FREQ=YEARLY;BYMONTH=9;BYDAY=3TU', '20240917T090000', 'the third Tuesday of September, a year on')
  end

  it 'UNTIL is inclusive, and a timed UNTIL is a moment, not a date' do
    # 06:59:59Z is 08:59:59 in Brussels, before the 09:00 occurrence
    no('FREQ=DAILY;UNTIL=20260915T065959Z', '20260901T090000', 'an occurrence after the series ended was drawn')
    yes('FREQ=DAILY;UNTIL=20260915T070000Z', '20260901T090000', 'the last occurrence, exactly at UNTIL, was dropped')
    yes('FREQ=DAILY;UNTIL=20260915', '20260901T090000', 'a date UNTIL does not include its own day')
  end

  it 'EXDATE still takes a day out, and a rule this does not read shows only its first date' do
    no('FREQ=DAILY', '20260901T090000', 'an excluded day was drawn', exdate: '20260915T090000')
    no('FREQ=YEARLY;BYWEEKNO=38', '20250915T090000', 'a week-number rule was guessed at')
  end
end
