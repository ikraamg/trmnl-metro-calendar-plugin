# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/line-slots.spec.js.
RSpec.describe 'line-slots' do
  include TransformC::Helpers

  let(:mocks) do
    feeds = { 'https://x.example/a.ics' => feed('Alpha', '1200'), 'https://x.example/b.ics' => feed('Bravo', '0900'),
              'https://x.example/c.ics' => feed('Charlie', '1500'), 'https://x.example/d.ics' => feed('Delta', '1800') }
    feeds.merge('*' => "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n")
  end

  def feed(summary, hour_minute)
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:#{summary}\r\n" \
      "DTSTART:20260919T#{hour_minute}00Z\r\nDTEND:20260919T#{hour_minute}30Z\r\nSUMMARY:#{summary}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  end

  def config(names)
    JSON.generate(version: 1, lines: names.map { { name: it } },
                  calendars: names.map { { url: "https://x.example/#{it[0].downcase}.ics", line: it } })
  end

  def board(config_json, state: nil) = run_transform(now: '2026-09-19T10:00:00Z', fields: { config_json: }, mocks:, state:)

  # keys in name order, so the comparison is about the rungs and not the order the legend arrived in
  def slots(run) = TransformC.payload(run)['legend'].map { [it['name'], it['slot']] }.sort.to_h

  it "every person gets a rung, in the legend's order the first time, and it is saved" do
    run = board(config(%w[Alpha Bravo Charlie]))

    expect(slots(run)).to eq('Alpha' => 0, 'Bravo' => 1, 'Charlie' => 2)
    expect(run.state['lineSlots']).to eq('Alpha' => 0, 'Bravo' => 1, 'Charlie' => 2)
  end

  it 'the rungs come back from the state whatever order the legend arrives in' do
    run = board(config(%w[Charlie Alpha Bravo]), state: { lineSlots: { Alpha: 0, Bravo: 1, Charlie: 2 } })

    expect(slots(run)).to eq('Alpha' => 0, 'Bravo' => 1, 'Charlie' => 2)
  end

  it 'somebody new takes the lowest free rung; somebody gone frees theirs' do
    run = board(config(%w[Alpha Charlie Delta]), state: { lineSlots: { Alpha: 0, Bravo: 1, Charlie: 2 } })

    expect(slots(run)).to eq('Alpha' => 0, 'Charlie' => 2, 'Delta' => 1)
    expect(run.state['lineSlots']).to eq('Alpha' => 0, 'Charlie' => 2, 'Delta' => 1)
  end

  it "a shared calendar's line takes no rung" do
    shared = JSON.generate(version: 1, lines: [{ name: 'Alpha' }, { name: 'Bravo' }],
                           calendars: [{ url: 'https://x.example/a.ics', line: 'Alpha' }, { url: 'https://x.example/b.ics', line: 'Bravo' },
                                       { url: 'https://x.example/c.ics', name: 'Family' }])
    found = slots(board(shared))

    expect(found.values_at('Alpha', 'Bravo')).to eq([0, 1])
    expect(found['Family']).to be_nil, "the shared line took a rung: #{found['Family']}"
  end

  it 'junk in the saved rungs is dropped, not replayed' do
    run = board(config(%w[Alpha Bravo]), state: { lineSlots: { Alpha: 'x', Bravo: -3, '' => 2 } })

    expect(slots(run)).to eq('Alpha' => 0, 'Bravo' => 1)
  end
end
