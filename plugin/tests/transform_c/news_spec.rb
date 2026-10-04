# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/news.spec.js.
RSpec.describe 'news' do
  include TransformC::Helpers

  let(:now) { Time.iso8601('2026-09-19T10:00:00Z') }
  let(:cal) { 'https://calendar.example.com/a.ics' }
  let(:rss) do
    '<?xml version="1.0"?><rss version="2.0"><channel><title>Het Nieuwsblad - Regio</title>' \
      '<link>https://x.example</link>' \
      '<item><title>Older &amp; wiser</title><pubDate>Fri, 18 Sep 2026 08:00:00 GMT</pubDate><description><![CDATA[<p>x</p>]]></description></item>' \
      '<item><title><![CDATA[Brug in <b>Gent</b> dicht &#8211; omleiding]]></title><pubDate>Sat, 19 Sep 2026 09:30:00 GMT</pubDate></item>' \
      '<item><title></title><pubDate>Sat, 19 Sep 2026 09:45:00 GMT</pubDate></item>' \
      '</channel></rss>'
  end
  let(:atom) do
    '<?xml version="1.0" encoding="utf-8"?><feed xmlns="http://www.w3.org/2005/Atom"><title>School Wilgenhoek</title>' \
      '<link rel="self" href="https://s.example/feed"/><updated>2026-09-19T00:00:00Z</updated>' \
      '<entry><title>Pyjamadag vrijdag</title><published>2026-09-17T07:00:00Z</published><content type="html">&lt;p&gt;x&lt;/p&gt;</content></entry>' \
      '<entry><title>Schoolfeest 3 oktober</title><published>2026-09-18T07:00:00Z</published></entry>' \
      '</feed>'
  end

  # The calendar answers; each mapped URL answers its text, or (nil) drops the connection; anything else is a 404.
  def network(map) = { cal => "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n" }.merge(map.transform_values { it || { error: :reset } })

  def board(map, fields, at: now, state: nil) = run_transform(now: at, fields: { config_json: cal }.merge(fields), mocks: network(map), state:)

  it 'no News setting, no news on the board' do
    expect(TransformC.payload(board({}, {}))).to include('news' => nil)
  end

  it 'RSS and Atom are read, newest first and the feeds in turn' do
    run = board({ 'https://x.example/rss' => rss, 'https://s.example/feed' => atom },
                { news_feeds: "# the paper\nhttps://x.example/rss\nschool https://s.example/feed\n", news_count: '2' })
    news = TransformC.payload(run)['news']

    expect(news).to include('items'), 'no news came back'
    expect(news['max']).to eq(2)
    expect(news['items'].map { it['title'] })
      .to eq(['Brug in Gent dicht – omleiding', 'Schoolfeest 3 oktober', 'Older & wiser', 'Pyjamadag vrijdag'])
    expect(news['items'].map { it['source'] }).to eq(['Het Nieuwsblad', 'School Wilgenhoek', 'Het Nieuwsblad', 'School Wilgenhoek'])
  end

  it '"as many as fit on one row" travels as one row with the fit flag' do
    news = TransformC.payload(board({ 'https://x.example/rss' => rss }, { news_feeds: 'https://x.example/rss', news_count: 'fit' }))['news']

    expect([news['max'], news['fit'], news['items'].length]).to eq([1, true, 2])
  end

  it 'a feed that is not a feed, and one that is down, are left out' do
    run = board({ 'https://x.example/rss' => rss, 'https://h.example/' => '<html><body>hi</body></html>', 'https://d.example/' => nil },
                { news_feeds: "https://h.example/\nhttps://d.example/\nhttps://x.example/rss" })
    news = TransformC.payload(run)['news']

    expect(news['items'].length).to eq(2)
    # the default is the one row of as many as fit
    expect([news['max'], news['fit']]).to eq([1, true])
  end

  it 'the last headlines are kept for a refresh on which every feed is down' do
    saved = board({ 'https://x.example/rss' => rss }, { news_feeds: 'https://x.example/rss' }).state
    expect(saved.dig('news', 'items')&.length).to eq(2), 'the headlines were not saved'

    later = now + (30 * 60)
    replayed = board({ 'https://x.example/rss' => nil }, { news_feeds: 'https://x.example/rss' }, at: later, state: saved)
    expect(TransformC.payload(replayed)['news']&.dig('items')&.length).to eq(2), 'the saved headlines were not used'

    # ...but not forever, and not for a different set of feeds
    stale = board({ 'https://x.example/rss' => nil }, { news_feeds: 'https://x.example/rss' }, at: now + (7 * 3600), state: saved)
    expect(TransformC.payload(stale)).to include('news' => nil)
    other = board({ 'https://x.example/rss' => nil }, { news_feeds: 'https://other.example/rss' }, at: later, state: saved)
    expect(TransformC.payload(other)).to include('news' => nil)
  end

  it 'the example day carries the news too' do
    run = run_transform(now:, fields: { news_feeds: 'https://x.example/rss' },
                        mocks: { 'https://x.example/rss' => rss }.merge(TransformC.demo_mocks))

    expect(TransformC.payload(run)['news']&.dig('items')&.length).to eq(2), 'the demo board has no news'
  end
end
