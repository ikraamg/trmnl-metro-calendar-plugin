# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/hide-if-empty.spec.js.
RSpec.describe 'hide-if-empty' do
  include TransformC::Helpers

  let(:busy) { 'https://cal.example.com/busy.ics' }
  let(:quiet) { 'https://cal.example.com/quiet.ics' }
  let(:busy_ics) { TransformC.ics_with_events([{ summary: 'Standup', start: '20260909T090000Z', end: '20260909T091500Z' }]) }
  let(:empty_ics) { "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Quiet\r\nEND:VCALENDAR\r\n" }

  def board(config, down = false)
    run_transform(now: '2026-09-09T09:00:00Z', fields: { use_demo_data: 'false', config_json: JSON.generate(config) },
                  mocks: { busy => busy_ics, quiet => down ? { status: 503, body: '' } : empty_ics })
  end

  def tracks(run) = TransformC.payload(run)['legend'].map { it['name'] }.sort.join(',')

  it 'a line somebody named is on the board on its quiet day too' do
    run = board(lines: [{ name: 'Busy' }, { name: 'Quiet' }],
                calendars: [{ name: 'Busy', url: busy, rules: [{ match: { type: 'any' }, line: 'Busy' }] },
                            { name: 'Quiet', url: quiet, rules: [{ match: { type: 'any' }, line: 'Quiet' }] }])

    expect(tracks(run)).to eq('Busy,Quiet')
    expect(TransformC.events(run).length).to eq(1), 'expected the one real event'
  end

  it 'a calendar that only routes elsewhere does not become an empty rail' do
    run = board(lines: [{ name: 'Busy' }],
                calendars: [{ name: 'Busy', url: busy, rules: [{ match: { type: 'any' }, line: 'Busy' }] },
                            { name: 'School', url: quiet, rules: [{ match: { type: 'any' }, line: 'Busy' }] }])

    expect(tracks(run)).to eq('Busy')
  end

  it 'keepLine on a calendar keeps the line that calendar owns' do
    run = board(calendars: [{ name: 'Busy', url: busy }, { name: 'Quiet', url: quiet, keepLine: true }])

    expect(tracks(run)).to eq('Busy,Quiet')
  end

  it 'a kept calendar survives its feed being down, not just being empty' do
    run = board({ calendars: [{ name: 'Busy', url: busy }, { name: 'Quiet', url: quiet, keepLine: true }] }, true)

    expect(tracks(run)).to eq('Busy,Quiet')
  end

  it 'an unnamed kept calendar takes its line name from the feed' do
    run = board(calendars: [{ name: 'Busy', url: busy }, { url: quiet, keepLine: true }])

    expect(tracks(run)).to eq('Busy,Quiet')
  end

  it 'hideWhenEmpty drops a line that is only worth drawing when used' do
    run = board(lines: [{ name: 'Busy' }, { name: 'Quiet', hideWhenEmpty: true }],
                calendars: [{ name: 'Busy', url: busy, rules: [{ match: { type: 'any' }, line: 'Busy' }] },
                            { name: 'Quiet', url: quiet, rules: [{ match: { type: 'any' }, line: 'Quiet' }] }])

    expect(tracks(run)).to eq('Busy')
  end
end
