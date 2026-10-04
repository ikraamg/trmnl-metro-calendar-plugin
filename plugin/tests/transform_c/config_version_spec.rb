# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/config-version.spec.js. The household and demo migration cases and the
# checker call migrateConfig/configWarnings inside transform.js, so they stay in the Node runner.
RSpec.describe 'config-version' do
  include TransformC::Helpers

  let(:now) { '2026-09-15T14:00:00Z' }
  let(:feed) do
    rows = ['BEGIN:VEVENT', 'UID:1@x', 'SUMMARY:L2 - Zwemmen', 'DTSTART;TZID=Europe/Brussels:20260915T090000',
            'DTEND;TZID=Europe/Brussels:20260915T100000', 'END:VEVENT',
            'BEGIN:VEVENT', 'UID:2@x', 'SUMMARY:Sportdag', 'DTSTART;TZID=Europe/Brussels:20260915T130000',
            'DTEND;TZID=Europe/Brussels:20260915T140000', 'END:VEVENT']
    (['BEGIN:VCALENDAR', 'VERSION:2.0'] + rows + ['END:VCALENDAR', '']).join("\r\n")
  end

  def payload_for(config)
    TransformC.payload(run_transform(now:, fields: { config_json: JSON.generate(config) }, mocks: { '*' => feed },
                                     time_zone: 'Europe/Brussels'))
  end

  def by_line(data)
    names = (data['legend'] || []).to_h { [it['key'], it['name']] }
    (data['events'] || []).map do |event|
      owners = ([event['owner']] + (event['co_owners'] || [])).map { names[it] }.sort.join('+')
      "#{event['title']} @ #{owners}"
    end.sort
  end

  it 'the format: a calendar says whose it is with line, and a rule naming a line leaves the title alone' do
    data = payload_for(version: 1, lines: [{ name: 'Mia' }, { name: 'Noah' }],
                       calendars: [{ url: 'https://example.com/school.ics', name: 'School', line: %w[Mia Noah],
                                     rules: [{ match: { type: 'word', value: 'L2' }, line: 'Mia' }] }])

    expect(by_line(data)).to eq(['L2 - Zwemmen @ Mia', 'Sportdag @ Mia+Noah'])
    expect((data['legend'] || []).map { it['name'] }.sort).to eq(%w[Mia Noah]), "the calendar's name became a line"
  end

  it 'the format: title replaces the whole title, rewrite cuts, and name is a line only without lines' do
    data = payload_for(version: 1, calendars: [{ url: 'https://example.com/school.ics', name: 'School',
                                                 rules: [{ match: { type: 'regex', value: '^L\\d\\s*-\\s*' }, rewrite: '' },
                                                         { match: { type: 'contains', value: 'Sport' }, title: 'Sports day' }] }])

    expect(by_line(data)).to eq(['Sports day @ School', 'Zwemmen @ School'])
  end

  it 'a not written with matchers is read as none of them, not dropped' do
    data = payload_for(version: 1, lines: [{ name: 'Mia' }],
                       calendars: [{ url: 'https://example.com/school.ics', line: 'Mia',
                                     rules: [{ match: { type: 'not', matchers: [{ type: 'contains', value: 'Zwemmen' }] },
                                               hide: true }] }])

    expect(by_line(data)).to eq(['L2 - Zwemmen @ Mia'])
  end
end
