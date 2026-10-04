# frozen_string_literal: true

require 'erb'
require 'tzinfo'
require_relative '../support/layout_extra'

# Ported from test/trmnl/households/households.spec.js: six invented households through the whole pipeline. The feed
# checks FAIL; on the boards a fault fails, except the ones in KNOWN, which must keep faulting exactly so.
RSpec.describe 'households' do
  dir = File.join(MetroLayout::REPOSITORY, 'test', 'households')
  known = {
    'multigen-chicago sat-0800 og-landscape' => ['namecut:  / p1'],
    'multigen-chicago wed-0800 og-half-vertical' => ['names:  / Zoe'],
    'multigen-chicago sat-0800 og-half-vertical' => ['names: Eli / Zoe'],
    'multigen-chicago wed-0800 og-quadrant' => ['names:  / Zoe'],
    'single-parent-be sat-0800 og-half-horizontal' => ['names: Liesbeth / Fien'],
    'single-parent-be sat-0800 og-quadrant' => ['namecut: L / p2']
  }
  slugs = Dir.children(dir).select { File.exist?(File.join(dir, it, 'config.json')) }.sort
  times = [
    { key: 'tue-0730', date: '2026-09-15', hm: '07:30' }, { key: 'tue-1200', date: '2026-09-15', hm: '12:00' },
    { key: 'tue-1630', date: '2026-09-15', hm: '16:30' }, { key: 'tue-2130', date: '2026-09-15', hm: '21:30' },
    { key: 'wed-0800', date: '2026-09-16', hm: '08:00' }, { key: 'sat-0800', date: '2026-09-19', hm: '08:00' }
  ]
  views = {
    'x-landscape' => { device: 'v2' }, 'x-portrait' => { device: 'v2', orientation: :portrait },
    'og-landscape' => { device: 'og_png' }, 'og-half-horizontal' => { device: 'og_png', view: 'half_horizontal' },
    'og-half-vertical' => { device: 'og_png', view: 'half_vertical' }, 'og-quadrant' => { device: 'og_png', view: 'quadrant' }
  }

  # ---------------------------------------------------------------- transform

  def feed_base(url) = url.to_s.split('?').first.split('/').last.to_s.gsub(/%\h\h/) { [it[1..]].pack('H*') }.force_encoding('UTF-8')

  # A feed is served by the last segment of its URL's path, from the household's own folder; a language from i18n/.
  def mocks_for(dir, config)
    feeds = (config['calendars'] || []).filter_map do |calendar|
      base = feed_base(calendar.is_a?(String) ? calendar : calendar['url'])
      file = File.join(dir, base)
      next unless base.end_with?('.ics') && File.exist?(file)

      [%r{/#{Regexp.escape(base.gsub(/[^A-Za-z0-9._-]/) { ERB::Util.url_encode(it) })}(\?.*)?\z}, File.read(file)]
    end
    feeds.uniq(&:first).to_h.merge(MetroLayout.demo_mocks.select { |url, _| url.include?('/i18n/') }, MetroLayout::NOT_FOUND)
  end

  def transform_at(dir, slug, time)
    folder = File.join(dir, slug)
    text = File.read(File.join(folder, 'config.json'))
    config = JSON.parse(text)
    zone = config['timeZone'] || 'UTC'
    year, month, day = time[:date].split('-').map(&:to_i)
    hour, minute = time[:hm].split(':').map(&:to_i)
    now = TZInfo::Timezone.get(zone).local_to_utc(Time.utc(year, month, day, hour, minute))
    # TRMNL fills settings.yml's defaults (setup_mode: links), so the case says which box to read
    run = trmnl.transform(device: 'og_png', now:, data: {}, mocks: mocks_for(folder, config),
                          custom_fields: { use_demo_data: 'false', setup_mode: 'config', config_json: text },
                          variables: { trmnl: { user: { locale: (config['locale'] || 'en').split('-').first, time_zone_iana: zone },
                                                plugin_settings: { instance_name: 'Household' } } })
    expect(run.error).to be_nil, "#{slug} #{time[:key]}: #{run.error}"
    expect(run).to stay_within_serverless_limits
    { data: run.data['data'], config:, dir: folder }
  end

  # ---------------------------------------------------------------- payload helpers

  PayloadView = Struct.new(:data, :events, :all_day, :lines, :holidays) do
    def find(pattern, day = nil) = events.select { pattern.match?(it['title']) && (day.nil? || (it['start_min'] / 1440).floor == day) }

    def find_all_day(pattern, day = nil) = all_day.select { pattern.match?(it['title']) && (day.nil? || (it['day'] || 0) == day) }
  end

  def view_of(data)
    names = (data['legend'] || []).to_h { [it['key'], it['name']] }
    events = (data['events'] || []).map do |event|
      event.merge('who' => ([event['owner']] + (event['co_owners'] || [])).map { names[it] || it }.sort)
    end
    all_day = (data['all_day'] || []).map { |item| item.merge('who' => (item['owners'] || []).map { names[it] || it }.sort) }
    PayloadView.new(data, events, all_day, (data['legend'] || []).map { it['name'] }, data['holidays'] || [])
  end

  def hhmm(min)
    min = min.round
    clock = min % 1440
    days = (min / 1440.0).floor
    prefix = if days.positive? then "+#{days}d" elsif days.negative? then "#{days}d" else '' end
    format('%<prefix>s%<hour>02d:%<minute>02d', prefix:, hour: clock / 60, minute: clock % 60)
  end

  def who(event) = event['who'].join(',')

  # ---------------------------------------------------------------- what the feeds say

  # Each returns [ok, message] pairs; `at[key]` is the view of that time's payload.
  def checks(slug, at)
    case slug
    when 'single-parent-be'
      v = at['tue-1630']
      w = at['tue-2130']
      s = at['sat-0800']
      bins = v.find(/PMD|Papier|Glas/, 0)
      woe = w.find(/Woensdagnamiddag/, 1)
      papa = s.find_all_day(/Kinderen bij Pieter/)
      [
        [bins.size == 1, "bins due 19:00 merged into ONE stop (got #{bins.size}: #{bins.map { "#{it['title']}@#{hhmm(it['start_min'])}" }.join(', ')})"],
        [bins.any? && bins[0]['start_min'] == 19 * 60, "bins at 19:00 wall clock despite Z (got #{bins[0] ? hhmm(bins[0]['start_min']) : '-'})"],
        [bins.any? && !!bins[0]['todo'] && (bins[0]['parts'] || []).size == 3, "bins stop is a task with 3 parts (#{bins[0]&.dig('parts').to_json})"],
        [v.find(/Restafval/, 0).empty?, 'completed Restafval task (14 Sep) is absent'],
        [v.find(/5A|6B|Technopolis/).empty? && v.find_all_day(/Technopolis/).empty?, 'other classes (5A, 6B, 3C) hidden'],
        [v.find(/^Zwemmen$/, 0).any? { who(it) == 'Jonas' }, '5B Zwemmen -> Jonas, code stripped'],
        [v.find(/^Bibliotheek$/, 0).any? { who(it) == 'Fien' }, '2A Bibliotheek -> Fien'],
        [v.find(/schoolfotograaf/i, 0).any? { who(it) == 'Fien,Jonas' }, 'Alle klassen: schoolfotograaf shared by both kids'],
        [v.find(/Teamoverleg/, 0).size == 1 && v.find(/Teamoverleg/, 0)[0]['start_min'] == 690, 'RECURRENCE-ID moves Teamoverleg to 11:30 once'],
        [v.find(/Kapper/).empty?, 'cancelled Kapper hidden'],
        [woe.size == 1 && who(woe[0]) == 'Fien,Jonas', 'INTERVAL=2 Wednesday afternoon at papa appears tomorrow for both kids (21:30 board)'],
        # a week is a state of the line, at its head, not a stop on the clock
        [papa.size >= 1 && s.find(/Kinderen bij Pieter/).empty?, "custody week that began Fri 18:00 (INTERVAL=2) is at the head of Saturday's board (got #{papa.size})"],
        [at['tue-1630'].find(/Kinderen bij Pieter/, 0).empty?, 'no custody block on an off week (Tue 15)']
      ]
    when 'nurse-couple-uk'
      v = at['tue-1630']
      m = at['tue-0730']
      w = at['wed-0800']
      night = v.find(/Night/, 0)
      stand_up = m.find(/stand-up/i, 0)
      [
        [night.size == 1 && night[0]['start_min'] == (19 * 60) + 30 && night[0]['end_min'] == 1440 + (8 * 60),
         "Tue night shift 19:30 -> Wed 08:00 spans midnight (got #{night.map { "#{it['start_min']}-#{it['end_min']}" }.join(',')})"],
        [w.find(/Night/).any? { it['start_min'].negative? || it['start_min'].zero? || it['end_min'] == 8 * 60 }, 'Wed 08:00 board still shows the night shift ending at 08:00 (it started yesterday)'],
        [m.find(/Pilates/, 0).size == 1, 'Pilates COUNT=8 week 3 present'],
        [m.find(/Spin/).empty?, 'Spin class COUNT=8 (ended Aug) absent'],
        [v.find(/Book club/, 0).size == 1, 'Book club BYDAY=3TU present on 15 Sep'],
        [v.find(/Choir/).empty?, 'Choir BYDAY=2TU absent on 15 Sep'],
        [stand_up.size == 1 && stand_up[0]['start_min'] == (9 * 60) + 45, "stand-up moved to 09:45 by RECURRENCE-ID, once (got #{stand_up.map { hhmm(it['start_min']) }.join(',')})"],
        [v.find(/Marcus/).empty?, 'cancelled 1:1 hidden'],
        [at['sat-0800'].find(/Early|LD|Long day/, 0).size >= 1, 'Sat early shift present'],
        [at['tue-2130'].find(/Football|5-a-side/).empty?, '5-a-side past UNTIL absent']
      ]
    when 'multigen-chicago'
      v = at['tue-1200']
      s = at['sat-0800']
      dinner = s.find(/Aunt Carol/, 0)
      [
        [v.data['hour12'] == true, '12h clock'],
        [v.lines.size == 7, "7 lines (got #{v.lines.join(',')})"],
        [v.find(/^Piano/, 0).any? { who(it) == 'Mia' }, 'Mia: Piano routed to Mia and prefix stripped'],
        [v.find(/Cardiology/, 0).any? { who(it) == 'Walt' }, 'Grandpa: routed to Walt'],
        [v.find(/^(Mia|Eli|Zoe|Grandpa|Grandma|Mom|Dad|Everyone)\b.*:/).empty?,
         "no name prefix left in any title (#{v.find(/^[A-Z][a-z]+( & [A-Z][a-z]+)?:/).map { it['title'] }.join(' | ')})"],
        [v.find(/PT|Physical therapy/i, 0).size == 1, 'Grandma PT COUNT=12 still running on 15 Sep'],
        [dinner.size == 1 && dinner[0]['who'].size == 7, 'Everyone: dinner shared by all 7'],
        [at['tue-2130'].find(/Dentist/, 1).any? { who(it) == 'Eli,Mia' }, 'Mia & Eli: Dentist shared by the two'],
        [at['tue-1630'].find(/Rx|prescription/i, 0).size == 1, 'Rx pickup task present']
      ]
    when 'flatshare-berlin'
      v = at['tue-1200']
      w = at['tue-2130']
      s = at['sat-0800']
      tobias = v.events.select { it['who'].include?('Tobias') }
      party = w.find(/Party/i, 1)
      [
        [v.lines.include?('Tobias') == tobias.any?, "Tobias (hideIfEmpty) in the legend only when he has something today or tomorrow (lines #{v.lines.join(',')}; his: #{tobias.map { it['title'] }.join(',')})"],
        [s.lines.include?('Tobias'), 'Tobias present on Saturday'],
        [party.size == 1 && party[0]['who'].size >= 3, "WG-Party tomorrow is one shared event (got #{party.map { it['who'].join('+') }.join(' | ')})"],
        [v.find(/.*/, 0).count { who(it) == 'Moritz' } >= 6, 'Moritz has his 6 back-to-back lectures'],
        [v.all_day.any? { /Küche|Putz/.match?(it['title']) } || v.find(/Putz|Küche/).any?, 'chores rotation (multi-day all-day, INTERVAL=4, series began in July) shows this week'],
        [w.find(/Homeoffice/, 1).size == 1, "weekday rule (WE) rewrites tomorrow's Werkstudentin block as Homeoffice"],
        [v.find(/Werkstudentin|Homeoffice/, 0).all? { /Werkstudentin/.match?(it['title']) }, 'weekday rule (WE) does not fire on Tuesday'],
        [v.find(/Lerngruppe/).empty?, 'cancelled Lerngruppe hidden']
      ]
    when 'remote-freelance-lyon'
      v = at['tue-1200']
      noisy = v.events.select { /\[(Teams|Zoom)\]|^(RE|TR|FW)\s*:|zoom\.us|\[[A-Z]+-\d+\]/i.match?(it['title']) }
      hq = v.find(/London HQ/, 0)
      dog = v.find(/Biscuit/, 0)
      camille = v.events.count { who(it) == 'Camille' && it['start_min'] < 1440 }
      julien = v.events.count { who(it) == 'Julien' && it['start_min'] < 1440 }
      stand_up = v.find(/Standup client ACME/, 0)
      [
        [noisy.empty?, "no [Teams]/[Zoom]/RE:/ticket noise left in titles (#{noisy.map { it['title'] }.join(' | ')})"],
        [v.find(/Focus|Pause café/).empty?, 'Focus time and coffee hidden'],
        [v.find(/Annulé|Point de fin de journée/).empty?, 'cancelled meeting hidden'],
        [hq.size == 1 && hq[0]['start_min'] == (14 * 60) + 30, "London HQ sync written in \"GMT Standard Time\" lands at 14:30 Paris (got #{hq.map { hhmm(it['start_min']) }.join(',')})"],
        [dog.size == 1 && dog[0]['who'].size == 2, 'dog walker shared by both'],
        [camille >= 10, "Camille has 10+ meetings today (#{camille})"],
        [julien >= 10, "Julien has 10+ meetings today (#{julien})"],
        [stand_up.size == 1 && stand_up[0]['start_min'] == (8 * 60) + 15, 'ACME standup moved to 08:15 by RECURRENCE-ID']
      ]
    when 'family-five-nl'
      v = at['tue-1630']
      n = at['tue-2130']
      w = at['wed-0800']
      s = at['sat-0800']
      week_off = v.find_all_day(/Studieweek|vrij/i, 0)
      film = n.find(/Film/, 0)
      [
        [v.holidays.any? { /Prinsjesdag/.match?(it['title']) && it['day'] == 0 }, "Prinsjesdag in the header on 15 Sep (#{v.holidays.to_json})"],
        [v.lines.include?('Pim'), 'quiet toddler Pim kept (hideIfEmpty false)'],
        [week_off.any? && week_off.all? { who(it) == 'Daan,Lotte' } && v.holidays.none? { /Studie/.match?(it['title']) },
         "school week off at Daan and Lotte's heads, not the header (#{week_off.map { [it['title'], it['who']] }.to_json})"],
        [film.size == 1 && film[0]['end_min'] > 1440, "teen film crosses midnight (end #{film[0]&.dig('end_min')})"],
        [w.find_all_day(/Riet/, 0).any? || w.find(/Riet/, 0).any?, 'yearly birthday (2016 series) on 16 Sep'],
        [s.find_all_day(/Kempervennen|Center Parcs/, 0).any?, 'multi-day trip on Saturday'],
        [s.find(/Hockeywedstrijd/, 0).empty?, 'EXDATE removes Saturday hockey match during the trip'],
        [s.events.any? { /Feest/.match?(it['title']) && it['end_min'] > 1440 }, 'Saturday party crosses midnight'],
        [v.lines.size == 5, "5 lines, no leaked calendar line (#{v.lines.join(',')})"]
      ]
    end
  end

  # ---------------------------------------------------------------- the feed checks

  slugs.each do |slug|
    it "households · #{slug} · the payload says what the feeds say" do
      payloads = {}
      aggregate_failures do
        times.each do |time|
          run = transform_at(dir, slug, time)
          payloads[time[:key]] = run[:data]
          expect(run[:data]['calendars_down'] || []).to eq([]), "#{slug} #{time[:key]}: calendars down"
          expect(run[:data]['demo_partial']).to be_nil, "#{slug} #{time[:key]}: transform fell back to the demo"
          missing = (run[:config]['calendars'] || []).map { it.is_a?(String) ? it : it['url'] }
                                                    .reject { File.exist?(File.join(run[:dir], feed_base(it))) }
          expect(missing).to eq([]), "#{slug}: config names feeds with no local file"
        end
        at = Hash.new { |_, key| raise "no payload for #{key}" }
        payloads.each { |key, data| at[key] = view_of(data) }
        (checks(slug, at) || []).each do |ok, message|
          puts "#{ok ? '  ok   ' : '  FAIL '}#{slug}: #{message}"
          expect(ok).to be(true), "#{slug}: #{message}"
        end
      end
    end
  end

  # ---------------------------------------------------------------- the boards, reported

  slugs.product(times).each do |slug, time|
    it "households · #{slug} · #{time[:key]} · every board" do
      data = transform_at(dir, slug, time)[:data]
      name_of = (data['legend'] || []).to_h { [it['key'], it['name']] }
      aggregate_failures do
        views.each do |name, viewport|
          debug = MetroLayout.board(trmnl, data, viewport)['debug']
          row = { view: name, lines: (data['legend'] || []).size, shed: debug['shed'] || 0, muddle: debug['muddle'] || 0,
                  dropped: (debug['dropped'] || []).map { name_of[it] || it }, faults: debug['faults'] || [] }
          key = "#{slug} #{time[:key]} #{name}"
          puts "#{key}: #{row.to_json}"
          if known[key]
            expect(row[:faults]).to eq(known[key]), "#{key} no longer has its known fault: take it out of KNOWN"
          else
            expect(row[:faults]).to eq([]), "#{key}: the board knows it is wrong"
          end
        end
      end
    end
  end
end
