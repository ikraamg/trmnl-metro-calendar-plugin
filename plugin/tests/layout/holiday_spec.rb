# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/holiday.spec.js: a holiday is a property of the day, stated beside its date.
RSpec.describe 'holiday' do
  # a slot narrow enough for a compact header, which none of the shared viewports is
  compact = { device: 'og_png', slot: [600, 480] }
  christmas = [{ title: 'Christmas Day', day_index: 0, day_span: 1, day_label: nil }]
  spring_break = [{ title: 'Spring Break', day_index: 2, day_span: 5, day_label: 'Day 3 of 5' }]
  # transform caps the list at one; what the drawing does with two it was handed anyway is worth pinning
  two = [{ title: 'Christmas Day', day_index: 0, day_span: 1, day_label: nil },
         { title: 'School Holiday', day_index: 4, day_span: 14, day_label: 'Day 5 of 14' }]

  let(:busy) { MetroLayout.fixture('busy-day') }

  def board(metro, viewport, holidays = nil)
    MetroLayout.board(trmnl, holidays ? metro.merge('holidays' => MetroLayout.deep_copy(holidays)) : metro, viewport)
  end

  # the parts of the first day badge, the run's first day, which is the day a holiday in the payload is about
  def badge_items(report, name) = ((report['badges'] || [])[0]&.dig('items') || []).select { MetroLayout.class?(it, name) }

  it 'the harness can see the day badge at all' do
    report = board(busy['metro'], 'x-landscape')

    expect(report['badges'] || []).not_to be_empty, 'no day badge was reported'
    expect(badge_items(report, 'metro-date').size).to eq(1), 'the badge has no date for a holiday to sit beside'
  end

  it 'the day is named beside its date, once' do
    report = board(busy['metro'], 'x-landscape', christmas)

    expect(badge_items(report, 'metro-holiday-name').map { it['text'] }).to eq(['Christmas Day']),
                                                                           'the holiday is not stated beside the date, or is stated twice'
  end

  it 'it sits with the date rather than below it' do
    report = board(busy['metro'], 'x-landscape', christmas)
    date = badge_items(report, 'metro-date')[0]
    name = badge_items(report, 'metro-holiday-name')[0]
    share = [date['y'] + date['h'], name['y'] + name['h']].min - [date['y'], name['y']].max

    expect(share).to be > [date['h'], name['h']].min * 0.5,
                     "the holiday is on its own row: date at y=#{date['y'].round}, holiday at y=#{name['y'].round}"
    expect(name['x']).to be > date['x'], 'the holiday should read after the date it qualifies'
  end

  MetroLayout::LAYOUT_VIEWPORTS.each_key do |name|
    it "the map is not charged for it: #{name}" do
      without = board(busy['metro'], name)
      with_it = board(busy['metro'], name, christmas)

      expect(with_it['canvas']['h'].round).to eq(without['canvas']['h'].round), 'the canvas lost height to a holiday'
      expect(with_it['paths'].size).to eq(without['paths'].size),
                                       'the drawing changed. A holiday is not a line, not a branch and not a mark'
      before, after = [without, with_it].map { (it['badges'] || [])[0] }
      if before && after
        expect(after['h'].round).to be <= before['h'].round + 1, 'the badge grew taller: the holiday wrapped onto a second line'
      end
    end
  end

  it 'nothing is drawn for it AT AN HOUR' do
    report = board(busy['metro'], 'x-landscape', christmas)
    said = report['labels'].select { it['text'].include?('Christmas Day') }

    expect(said.size).to eq(1), "the holiday is stated #{said.size} times on the canvas; it is one fact about one day"
    expect(MetroLayout.class?(said[0], 'metro-daybadge')).to be(true),
                                                           "\"Christmas Day\" is drawn as #{said[0]['cls']} at " \
                                                           "#{said[0]['x'].round},#{said[0]['y'].round}. It has no hour to put it at."
  end

  it 'it declares nobody to be away' do
    report = board(busy['metro'], 'x-landscape', christmas)

    expect(MetroLayout.paths_where(report, 'terminal-open').size).to eq(0),
                                                                     "a holiday opened a line's ends as if that person were on it"
    expect(MetroLayout.paths_where(report, 'origin-tie').size).to eq(0), 'a holiday tied the heads together as if it were one of them'
    expect(report['labels'].count { MetroLayout.class?(it, 'metro-route') }).to eq(0), "a holiday was declared at a line's head"
  end

  it 'inside a range it says which day of it this is' do
    report = board(busy['metro'], 'x-landscape', spring_break)
    day = badge_items(report, 'metro-holiday-day')

    expect(badge_items(report, 'metro-holiday-name').map { it['text'] }).to eq(['Spring Break'])
    expect(day.size).to eq(1), 'the range said nothing about where in it we are'
    expect(day[0]['text']).to include('Day 3 of 5'), "expected the ordinal, got #{day[0]['text'].to_json}"
  end

  it 'a squeezed badge keeps the name and drops the ordinal' do
    report = board(busy['metro'], compact, spring_break)
    shown = ->(name) { badge_items(report, name).select { it['shown'] } }

    expect(shown.call('metro-holiday-name').map { it['text'] }).to eq(['Spring Break']),
                                                                   'the name went with the ordinal, or the badge went entirely'
    expect(shown.call('metro-holiday-day').size).to eq(0),
                                                    'the ordinal survived onto a squeezed badge, where the name is what matters'
    expect(shown.call('metro-date').size).to eq(1), 'the date went: it is the one part of the badge that outlasts the rest'
  end

  it 'a day carrying two holidays names one of them' do
    report = board(busy['metro'], 'x-landscape', two)

    expect(badge_items(report, 'metro-holiday-name').map { it['text'] }).to eq(['Christmas Day']),
                                                                           'the badge drew more than one name, or the wrong one'
  end

  it 'the name reads before the weather, not through it' do
    report = board(busy['metro'], 'x-landscape', christmas)
    name = badge_items(report, 'metro-holiday-name').find { it['shown'] }
    weather = badge_items(report, 'metro-temp').select { it['shown'] }

    expect(name).to be_truthy, 'the holiday was not drawn at all on a roomy board'
    next if weather.empty? # a spent day keeps its name and gives up its numbers

    expect(name['x'] + name['w']).to be <= weather[0]['x'] + 1,
                                     "the holiday runs into the weather: it ends at #{(name['x'] + name['w']).round} " \
                                     "and the temperature starts at #{weather[0]['x'].round}"
  end

  it "a rolling board states the borrowed day's holiday on its own badge" do
    roll = MetroLayout.fixture('rolling-quiet')
    next unless roll # no two-day fixture to ask with

    # at five in the afternoon, when the board reaches into tomorrow
    evening = roll['metro'].merge('now_min' => 17 * 60)
    report = board(evening, 'x-landscape', [{ title: 'Boxing Day', day: 1, day_index: 0, day_span: 1, day_label: nil }])
    badges = report['badges'] || []
    expect(badges.size).to be >= 2, 'this board should carry a badge for each of its days'

    named = badges.map { |badge| (badge['items'] || []).select { MetroLayout.class?(it, 'metro-holiday-name') }.map { it['text'] } }
    expect(named[0]).to eq([]), "the opening day claimed the borrowed day's holiday"
    expect(named[1]).to eq(['Boxing Day']), "the borrowed day did not say what day it is: #{named.to_json}"
  end

  it 'a board with no holiday says nothing about one' do
    expect(badge_items(board(busy['metro'], 'x-landscape'), 'metro-holiday').size).to eq(0),
                                                                                     'an empty holiday list still drew its container'
  end
end
