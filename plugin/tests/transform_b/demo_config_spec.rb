# frozen_string_literal: true

require_relative '../support/transform_b'

# Ported from test/trmnl/transform/demo-config.spec.js.
RSpec.describe 'demo-config' do
  include TransformBHelpers

  demo_dir = TransformB::DEMO_DIR
  sets = { 'simpsons' => %w[Bart Homer Lisa Maggie Marge], 'futurama' => %w[Amy Bender Fry Leela Professor],
           'friends' => %w[Monica Rachel] }

  let(:now) { '2026-09-09T09:00:00Z' } # a Wednesday, so the weekday-limited entries (L6 Field Trip) are on

  # Every file under demo/, answered at any URL whose path ends in /main/demo/<show>/<file>; `missing` files and
  # anything else under /main/demo/ 404. `swap` answers a file with other text.
  def demo_files(missing: [], swap: {})
    files = Dir.glob('**/*', base: TransformB::DEMO_DIR).select { File.file?(File.join(TransformB::DEMO_DIR, it)) }.sort
    files.to_h do |rel|
      answer = missing.include?(rel) ? { status: 404 } : swap.fetch(rel) { File.read(File.join(TransformB::DEMO_DIR, rel)) }
      [%r{/main/demo/#{Regexp.escape(rel)}(\?.*)?$}, answer]
    end.merge(%r{/main/demo/} => { status: 404 })
  end

  # What a run fetched under demo/, relative to it.
  def demo_asked(run) = run.requests.map { it[:url] }.select { it.include?('/main/demo/') }.map { it.split('/main/demo/').last }

  def demo(mocks: demo_files, **fields) = board(now:, fields: { use_demo_data: 'true' }.merge(fields), mocks:)
  def names(data) = data['legend'].map { it['name'] }.sort
  def items(data) = data['events'] || []

  it 'the demo config resolves against the repo ICS files, with a line per family member' do
    expect(names(demo)).to eq(%w[Bart Homer Lisa Maggie Marge]), 'expected exactly the five family lines'
  end

  it 'a stale copy of one calendar shows through, because there is nothing to swap to' do
    stale = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Demo - School\r\n" \
            "BEGIN:VEVENT\r\nUID:stale@x\r\nDTSTAMP:20240101T000000Z\r\nSUMMARY:Zwemles L2\r\n" \
            "DTSTART:20240101T100000\r\nDTEND:20240101T110000\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU\r\n" \
            "END:VEVENT\r\nEND:VCALENDAR\r\n"
    data = demo(mocks: demo_files(swap: { 'simpsons/school.ics' => stale }))

    expect([names(data), items(data).size]).to match([include('Bart', 'Homer', 'Lisa', 'Maggie', 'Marge'), be_positive]),
                                                     'a stale feed cost the demo a line, or emptied the whole board'
  end

  it 'every demo calendar the config names actually exists in demo/' do
    seen = demo_asked(board_run(now:, fields: { use_demo_data: 'true' }, mocks: demo_files))

    expect([seen.reject { File.exist?(File.join(demo_dir, it)) }, seen.size >= 5]).to eq([[], true]),
                                                                                       'config points at a file not in ' \
                                                                                       'demo/, or fetched under five'
  end

  it 'school entries land on the right child by class code' do
    data = demo
    key = data['legend'].to_h { [it['name'], it['key']] }
    school_days = items(data).select { it['title'] == 'School Day' && it['start_min'] < 1440 }
    field_trip = items(data).to_h { [it['title'], it['owner']] }['Field Trip']

    expect([school_days.map { ([it['owner']] + it['co_owners']).sort }, field_trip])
      .to eq([[key.values_at('Bart', 'Lisa').sort], key['Bart']]),
          'one school day shared by Bart and Lisa, and the L6 field trip on Bart'
  end

  it 'the family calendar produces an interchange across everyone' do
    dinner = items(demo).find { it['title'].match?(/Family Dinner/) }

    expect(dinner&.fetch('co_owners')&.size).to be >= 3
  end

  it 'a partly-resolved demo still shows the whole family' do
    data = demo(mocks: demo_files(missing: %w[simpsons/homer.ics simpsons/marge.ics simpsons/maggie.ics]))

    expect(names(data)).to include('Bart', 'Homer', 'Lisa', 'Maggie', 'Marge'), 'a feed being down cost the demo a line'
  end

  it 'an unreachable GitHub draws an empty board, not a made-up one' do
    data = demo(mocks: { '*' => { status: 500 } })

    expect([items(data).size, data['legend'].size, data['header_weather']]).to match([0, 0, be_truthy]),
                                                                                'an offline board invented events or ' \
                                                                                'lines, or lost its header'
  end

  sets.each do |set, lines|
    it "the \"#{set}\" demo resolves against the repo ICS files" do
      data = demo(demo_set: set)

      expect([names(data), items(data).size]).to match([lines, be_positive])
    end
  end

  it 'an unknown demo board falls back to Springfield rather than an empty one' do
    expect(names(demo(demo_set: 'the-wire'))).to eq(sets['simpsons'])
  end

  it 'the Planet Express delivery is one long event on three lines' do
    data = demo(demo_set: 'futurama')
    runs = items(data).select { it['title'] == 'Delivery Run' && it['start_min'] < 1440 }
    position = data['legend'].each_with_index.to_h { |line, index| [line['key'], index] }
    crew = runs.map { ([it['owner']] + it['co_owners']).map { position[it] }.sort }

    expect(crew.map { [it.size, it.last - it.first] }).to eq([[3, 2]]),
                                                         'one Delivery Run, on three lines that sit next to each other'
  end

  it 'every demo board names files that exist, and only its own' do
    reached = sets.keys.to_h do |set|
      [set, demo_asked(board_run(now:, fields: { use_demo_data: 'true', demo_set: set }, mocks: demo_files))]
    end

    expect(reached).to all(satisfy { |set, seen| seen.any? && seen.all? { it.start_with?("#{set}/") && File.exist?(File.join(demo_dir, it)) } })
  end

  it 'demo/<show>/config.json IS the board the plugin runs, and every one of them parses' do
    sets.each_key do |name|
      cfg = JSON.parse(File.read(File.join(demo_dir, name, 'config.json')))

      expect(cfg).to include('calendars' => be_an(Array).and(be_any), 'lines' => be_an(Array).and(be_any))
      expect(cfg['calendars'].map { it['url'].to_s }).to all(match(%r{/main/demo/}))
    end
  end

  it 'demo-config.json, the example everyone copies, still draws a board' do
    cfg = File.read(File.join(TransformB::REPO, 'demo-config.json'))
    data = board(now:, fields: { config_json: cfg },
                 mocks: demo_files.merge('*' => "BEGIN:VCALENDAR\nEND:VCALENDAR\n"))
    titles = items(data).map { it['title'] }
    dinner = items(data).find { it['title'].match?(/Family Dinner/) }

    expect([!data['service_alert'], names(data), titles.size.positive?, titles.grep(/^(?:L6|K3)\s/),
            dinner && (dinner['co_owners'] || []).size])
      .to eq([true, JSON.parse(cfg)['lines'].map { it['name'] }.sort, true, [], dinner && 4])
  end

  it 'a config that names no calendars shows the example day, as the settings promise' do
    texts = ['{}', '{"version": 1}', '{"lines": [], "calendars": []}']
    boards = texts.to_h { [it, board(now:, fields: { config_json: it }, mocks: demo_files)] }

    expect(boards.transform_values { [it['legend'].any?, it.fetch('board_notice', :absent)] })
      .to eq(texts.to_h { [it, [true, nil]] })
  end

  it 'text that is neither a config nor a link says so, instead of showing the example' do
    data = board(now:, fields: { config_json: 'my calendars' }, mocks: demo_files)

    expect([data['legend'].size, data['board_notice']]).to match([0, /could not be read/])
  end

  it 'a retired calendar_urls value is not drawn when Calendars is empty' do
    data = board(now:, fields: { config_json: '', calendar_urls: 'https://raw.githubusercontent.com/x/y/main/demo/friends/rachel.ics' },
                 mocks: demo_files)

    expect([names(data).grep(/Rachel/), data['legend'].any?]).to eq([[], true])
  end

  it 'a plain list of ICS links needs no JSON and no editor' do
    data = board(now:, fields: { config_json: %w[https://raw.githubusercontent.com/x/y/main/demo/friends/monica.ics
                                                 https://raw.githubusercontent.com/x/y/main/demo/friends/rachel.ics].join("\n") },
                 mocks: demo_files)

    expect([names(data), items(data).size]).to match([['Demo - Monica', 'Demo - Rachel'], be_positive])
  end

  it 'a link to a feed with no name of its own is named from the link' do
    nameless = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" \
               "BEGIN:VEVENT\r\nUID:n@x\r\nDTSTAMP:20240101T000000Z\r\nSUMMARY:Standup\r\n" \
               "DTSTART:20240101T090000\r\nDTEND:20240101T091500\r\n" \
               "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    data = board(now:, fields: { config_json: 'https://cloud.example.com/alex-work.ics' }, mocks: { '*' => nameless })

    expect(data['legend'].map { it['name'] }).to eq(['Alex Work'])
  end
end
