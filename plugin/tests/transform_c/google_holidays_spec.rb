# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/google-holidays.spec.js. The first case's feedUrl assertions call
# transform.js's internal function directly, so they stay in the Node runner; its run is checked here.
RSpec.describe 'google-holidays' do
  include TransformC::Helpers

  let(:bad) { 'https://calendar.google.com/calendar/ical/en.belgian%23holiday%40group.v.calendar.google.com/public/basic.ics' }
  let(:good) { 'https://calendar.google.com/calendar/ical/en.be%23holiday%40group.v.calendar.google.com/public/basic.ics' }
  let(:feed) do
    "BEGIN:VCALENDAR\r\nPRODID:-//Google Inc//Google Calendar 70.9054//EN\r\nVERSION:2.0\r\n" \
      "CALSCALE:GREGORIAN\r\nMETHOD:PUBLISH\r\nX-WR-CALNAME:Holidays in Belgium\r\nX-WR-TIMEZONE:UTC\r\n" \
      "#{day('20211111', 'Armistice Day')}#{day('20261025', 'Daylight Saving Time ends', 'obs')}" \
      "#{day('20261101', "All Saints' Day")}#{day('20261111', 'Armistice Day')}" \
      "#{day('20261225', 'Christmas Day')}#{day('20261226', 'Boxing Day')}#{day('20311111', 'Armistice Day')}" \
      "END:VCALENDAR\r\n"
  end

  def day(date, summary, what = nil)
    finish = (Date.strptime(date, '%Y%m%d') + 1).strftime('%Y%m%d')
    description = if what == 'obs'
                    "DESCRIPTION:Observance\\nTo hide observances\\, go to Google Calendar Setting\r\n s > Holidays in Belgium\r\n"
                  else
                    "DESCRIPTION:Public holiday\r\n"
                  end
    "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:#{date}\r\nDTEND;VALUE=DATE:#{finish}\r\n" \
      "DTSTAMP:20260914T234036Z\r\nUID:#{date}_x@google.com\r\nCLASS:PUBLIC\r\n#{description}" \
      "SEQUENCE:0\r\nSTATUS:CONFIRMED\r\nSUMMARY:#{summary}\r\nTRANSP:TRANSPARENT\r\nEND:VEVENT\r\n"
  end

  # Google as it answers: the right id is the feed, anything else a 500.
  def brussels(now, config)
    run_transform(now:, fields: { config_json: config }, mocks: { good => feed, '*' => { status: 500, body: '' } },
                  time_zone: 'Europe/Brussels')
  end

  it "the wizard's old Belgian holiday link is read from the one Google serves" do
    run = brussels('2026-11-11T08:00:00Z', JSON.generate(calendars: [{ url: bad, holiday: true }]))
    data = TransformC.payload(run)

    expect(TransformC.urls(run)).to eq([good])
    expect((data['holidays'] || []).map { [it['title'], it['day']] }).to eq([['Armistice Day', 0]])
    expect(data['legend']).to eq([]), 'a holiday feed drew a line'
  end

  it "a link list with the holiday word names tomorrow's holiday in the account's zone" do
    data = TransformC.payload(brussels('2026-12-24T22:30:00Z', "#{good} holiday"))
    got = (data['holidays'] || []).map { [it['title'], it['day']] }

    expect(got).to include(['Christmas Day', 1]), "Christmas is not tomorrow: #{got}"
    expect(got).not_to include(['Christmas Day', 0]), 'Christmas was announced a day early'
  end

  it 'a Google holiday link is a holiday feed without the word' do
    now = '2026-11-11T08:00:00Z'
    data = TransformC.payload(brussels(now, "Belgium #{good}"))
    expect((data['holidays'] || []).map { it['title'] }).to eq(['Armistice Day']), 'the Google feed was not read as holidays'
    expect(data['legend']).to eq([]), 'a Google holiday feed drew a line'

    as_line = TransformC.payload(brussels(now, JSON.generate(calendars: [{ url: good, holiday: false, line: 'BE' }])))
    expect(as_line['legend'].map { it['name'] }).to eq(['BE']), 'holiday: false did not win'
  end

  it 'a day with no holiday in the feed has none, and nothing is down' do
    data = TransformC.payload(brussels('2026-09-15T08:00:00Z', "#{good} holiday"))

    expect([data['holidays'], data['calendars_down']]).to eq([[], []])
  end
end
