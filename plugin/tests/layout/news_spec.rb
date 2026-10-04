# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/news.spec.js: the one row of headlines, clamped (rule 2i).
RSpec.describe 'news' do
  views = { 'og-landscape' => 800, 'x-landscape' => 1872 } # each view's screen width
  titles = ['Nieuwe speeltuin in het Citadelpark opent zaterdag om tien uur',
            'Werken aan de Dampoort: tram 4 rijdt een maand niet, bussen vervangen',
            'Gentse Feesten 2027 krijgen een extra dag en een tweede podium',
            'Stad Gent plant 300 extra bomen langs de Coupure en de Leie',
            'Zwembad Rozebroeken twee weken dicht voor onderhoud van de filters',
            'Bibliotheek De Krook opent zondag ook in de namiddag tot zes uur']

  let(:busy) { MetroLayout.fixture('busy-day') }

  define_method(:news) do |sources|
    { max: 1, fit: true, items: titles.each_with_index.map { |title, index| { title:, source: sources[index % sources.size] } } }
  end

  def row_of(report) = report['labels'].find { it['cls'].include?('metro-news-row') && !it['cls'].include?('metro-banner') }

  it 'one row, clamped: the headlines are cut where the row ends, inside the box' do
    views.each do |name, width|
      report = MetroLayout.layout(trmnl, busy, name, news: news(['Het Nieuwsblad']))
      row = row_of(report)
      expect(row).to be_truthy, "#{name}: no headline row"
      expect(row['x'] + row['w']).to be <= report['canvas']['w'] + 0.5,
                                     "#{name}: the row runs out of the box: #{(row['x'] + row['w']).round} > #{report['canvas']['w']}"

      # one line: no taller than a label and a half
      line_height = row['h']
      expect(line_height).to be < 40 * (width > 1000 ? 2 : 1), "#{name}: the row wrapped, #{line_height.round}px tall"
      shown = titles.count { row['text'].include?(it) }
      expect(shown >= 1 && shown < titles.size).to be(true), "#{name}: #{shown} whole headlines on the row"

      # the row ends in a cut headline, or the room left is too little for one
      left = report['canvas']['w'] - (row['x'] + row['w'])
      expect(row['text'].end_with?('…') || left < line_height * 0.6 * 10).to be(true),
                                                                              "#{name}: the row is not clamped: ends " \
                                                                              "\"#{row['text'][-20..]}\" with #{left.round}px to spare"
      expect(!row['cls'].include?('metro-pill') && !row['text'].include?('Het Nieuwsblad')).to be(true),
                                                                                              "#{name}: a lone source was named"
    end
  end

  it 'only the cut headline gives way: no headline is printed over the one beside it' do
    views.each_key do |name|
      row = row_of(MetroLayout.layout(trmnl, busy, name, news: news(['Het Nieuwsblad'])))
      expect(row).to be_truthy, "#{name}: no headline row"
      expect(row['parts'] && row['parts'].size >= 2).to be(true), "#{name}: the row reported no pieces"

      cut = row['parts'].select { it['clamp'] }
      expect(cut.size).to be <= 1, "#{name}: #{cut.size} headlines were told to clamp"
      row['parts'].reject { it['clamp'] }.each do |part|
        expect(part['over']).to be(false), "#{name}: \"#{part['text'][0, 40]}\" is squeezed #{part['w'].round}px wide " \
                                           'and prints over what is beside it'
      end
      # ...and the pieces still range one after another, left to right
      row['parts'].each_cons(2).with_index(1) do |(before, after), index|
        expect(after['x']).to be >= before['x'] + before['w'] - 0.5, "#{name}: piece #{index} starts before the one before it ends"
      end
    end
  end

  it 'two sources on the clamped row are named by their pills, in front of their headlines' do
    report = MetroLayout.layout(trmnl, busy, 'x-landscape', news: news(['Het Nieuwsblad', 'De Wilgenhoek']))
    row = row_of(report)
    expect(row).to be_truthy, 'no headline row'

    expect(row['x'] + row['w']).to be <= report['canvas']['w'] + 0.5, 'the row runs out of the box'
    expect(row['text'].start_with?('Het Nieuwsblad') && row['text'].match?(/·\s*De Wilgenhoek/)).to be(true),
                                                                                                  'the sources are not in front of their ' \
                                                                                                  "headlines: #{row['text'][0, 80]}"
  end
end
