# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/todo-feeds.spec.js.
RSpec.describe 'todo-feeds' do
  include TransformC::Helpers

  let(:bins) do
    items = [todo('Restafval', '20260915T190000Z'), todo('PMD', '20260915T190000Z'), todo('Papier-karton', '20260915T190000Z'),
             todo('Tuinafvalbak', '20260914T190000Z'), # yesterday evening
             todo('Glas', '20260915T180000Z', ['STATUS:COMPLETED'])]
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:recycle\r\n#{items.join("\r\n")}\r\nEND:VCALENDAR\r\n"
  end

  def todo(summary, due, extra = [])
    ['BEGIN:VTODO', "UID:#{summary}#{due}", 'DTSTAMP:20260916T000000Z', "SUMMARY;LANGUAGE=\"NL\":#{summary}", "DUE:#{due}",
     *extra, 'END:VTODO'].join("\r\n")
  end

  # minutes past today's midnight, the payload's own clock
  def today(calendar)
    config = JSON.generate(lines: [{ name: 'Bins' }], calendars: [{ url: 'https://example.com/bins.ics', name: 'Bins' }.merge(calendar)])
    run = run_transform(now: '2026-09-15T08:00:00Z', fields: { config_json: config }, mocks: { '*' => bins }, time_zone: 'Europe/Brussels')
    TransformC.events(run).select { it['start_min'] >= 0 && it['start_min'] < 1440 }
  end

  it 'a to-do is a stop at its due time, and one that is done is not' do
    due = today({})

    expect(due.map { it['title'] }.sort).to eq(%w[PMD Papier-karton Restafval]), 'the to-dos due today'
    # 19:00Z is 21:00 in Brussels in September
    expect(due.map { it['start_min'] }).to all(eq(21 * 60)), "due at #{due.map { it['start_min'] }.join(', ')}"
    expect(due).to all(satisfy { it['end_min'] == it['start_min'] }), 'a to-do has no length: it is a moment'
  end

  it "ignoreTimezone reads the feed's UTC times as the board's own clock" do
    due = today(ignoreTimezone: true)

    expect(due.length).to eq(3), "#{due.length} to-dos today"
    expect(due.map { it['start_min'] }).to all(eq(19 * 60)), "due at #{due.map { it['start_min'] }.join(', ')}, not 19:00"
  end

  it 'mergeSameTime makes things due at the same minute on one line one stop' do
    due = today(ignoreTimezone: true, mergeSameTime: true)

    expect(due.length).to eq(1), 'one stop for the three bins'
    expect(due[0]['title'].split(' · ').sort).to eq(%w[PMD Papier-karton Restafval]), 'every bin named once'
    # and as a list, so the board can set them a name to a row
    expect((due[0]['parts'] || []).sort).to eq(%w[PMD Papier-karton Restafval]), 'the names do not travel as a list'
  end

  it 'without mergeSameTime they stay separate, and a rule still acts on one of them' do
    expect(today(ignoreTimezone: true).length).to eq(3), 'three stops'

    due = today(ignoreTimezone: true, mergeSameTime: true, rules: [{ match: { type: 'contains', value: 'PMD' }, hide: true }])
    expect(due.length).to eq(1), 'still one stop'
    expect(due[0]['title']).not_to include('PMD'), "a hidden bin was merged in: #{due[0]['title']}"
  end
end
