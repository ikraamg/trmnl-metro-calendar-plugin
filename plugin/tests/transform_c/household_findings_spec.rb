# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/household-findings.spec.js.
RSpec.describe 'household-findings' do
  include TransformC::Helpers

  def ics(rows) = (['BEGIN:VCALENDAR', 'VERSION:2.0'] + rows + ['END:VCALENDAR', '']).join("\r\n")

  def ev(props) = ['BEGIN:VEVENT', "UID:#{rand}@x", *props, 'END:VEVENT']

  def board(feed, now, calendar = {}, zone = 'Europe/Brussels')
    config = JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Sam' }.merge(calendar)])
    TransformC.payload(run_transform(now:, fields: { config_json: config }, mocks: { '*' => feed }, time_zone: zone))
  end

  it 'a timed event of a day or more is a state at the head of the line, day by day' do
    feed = ics(ev(['SUMMARY:Kids at the other home', 'DTSTART;TZID=Europe/Brussels:20260911T180000',
                   'DTEND;TZID=Europe/Brussels:20260918T180000']))
    data = board(feed, '2026-09-15T06:00:00Z')
    heads = (data['all_day'] || []).select { it['title'].include?('Kids') && (it['day'] || 0).zero? }

    expect(data['events'].count { it['title'].include?('Kids') }).to eq(0), 'a week was drawn as a stop on the clock'
    expect(heads.length).to eq(1), 'the week is not at the head of the line on its fifth day'
  end

  it "a night shift that began yesterday is on this morning's board, and says when it began" do
    feed = ics(ev(['SUMMARY:Night shift', 'DTSTART:20260914T190000Z', 'DTEND:20260915T070000Z']))
    data = board(feed, '2026-09-15T05:00:00Z', {}, 'Europe/London')
    shift = data['events'].select { it['title'] == 'Night shift' && it['start_min'] < 1440 }

    expect(shift.length).to eq(1), 'the shift is gone from the morning it is still running'
    expect(shift[0]['start_min']).to eq(0), 'it does not start the board at midnight'
    expect(shift[0]['began_min']).to eq(-240), 'it does not say it began at 20:00 the evening before'
    expect(shift[0]['end_min']).to eq(480), 'it does not end at 08:00'
  end

  it 'clean-up rules add up: every matching rewrite cuts, in order' do
    feed = ics(ev(['SUMMARY:RE: [ACME-2231] Invitation : Design review', 'DTSTART;TZID=Europe/Brussels:20260915T100000',
                   'DTEND;TZID=Europe/Brussels:20260915T110000']))
    data = board(feed, '2026-09-15T06:00:00Z', rules: [
                   { match: { type: 'regex', value: '^RE:\\s*' }, rewrite: '' },
                   { match: { type: 'regex', value: '\\[[A-Z]+-\\d+\\]\\s*' }, rewrite: '' },
                   { match: { type: 'contains', value: 'Invitation :' }, rewrite: '' }
                 ])

    expect(data['events'].map { it['title'] }).to eq(['Design review']), 'only some of the rewrites were applied'
  end

  it 'a title that began with a capital keeps one after its prefix is cut' do
    feed = ics(ev(['SUMMARY:Mia logo', 'DTSTART;TZID=Europe/Brussels:20260915T160000', 'DTEND;TZID=Europe/Brussels:20260915T163000']))
    data = board(feed, '2026-09-15T06:00:00Z', rules: [{ match: { type: 'regex', value: '^Mia\\s+' }, rewrite: '' }])

    expect(data['events'].map { it['title'] }).to eq(['Logo']), 'the cut left a lower-case title'
  end

  it 'a weekday rule asks the weekday of the event, not of today' do
    feed = ics(ev(['SUMMARY:Office block', 'DTSTART;TZID=Europe/Brussels:20260916T090000',
                   'DTEND;TZID=Europe/Brussels:20260916T100000']))
    data = board(feed, '2026-09-15T19:30:00Z', rules: [
                   { match: { type: 'and', matchers: [{ type: 'weekday', value: ['WE'] }, { type: 'contains', value: 'Office' }] },
                     title: 'Wednesday office' }
                 ])
    tomorrow = data['events'].select { it['start_min'] >= 1440 }

    expect(tomorrow.map { it['title'] }).to eq(['Wednesday office']), "Wednesday's event was judged as a Tuesday"
  end

  it 'an Outlook zone name is read as the zone it names' do
    feed = ics(ev(['SUMMARY:London sync', 'DTSTART;TZID=GMT Standard Time:20260915T133000',
                   'DTEND;TZID=GMT Standard Time:20260915T143000']))
    data = board(feed, '2026-09-15T06:00:00Z', {}, 'Europe/Paris')

    expect(data['events'].map { it['start_min'] }).to eq([(14 * 60) + 30]), '13:30 in London is not 14:30 in Paris'
  end

  it 'a week-long all-day block repeating every four weeks comes back' do
    feed = ics(ev(['SUMMARY:Kitchen duty', 'DTSTART;VALUE=DATE:20260720', 'DTEND;VALUE=DATE:20260727',
                   'RRULE:FREQ=WEEKLY;INTERVAL=4']))
    data = board(feed, '2026-09-16T06:00:00Z')
    heads = (data['all_day'] || []).select { it['title'] == 'Kitchen duty' && (it['day'] || 0).zero? }

    expect(heads.length).to eq(1), 'the repeating week is missing'
  end
end
