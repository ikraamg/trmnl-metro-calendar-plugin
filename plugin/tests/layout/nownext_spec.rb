# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/nownext.spec.js: the now/next card, which only exists in a browser.
RSpec.describe 'nownext' do
  def card_of(report) = report['labels'].find { MetroLayout.class?(it, 'metro-nownext') }

  def badges_of(report) = report['labels'].select { MetroLayout.class?(it, 'metro-daybadge') && it['h'].positive? }

  def middle(box) = box['y'] + (box['h'] / 2.0)

  MetroLayout.fixtures.each do |fixture|
    it "the now/next card keeps off everything else in the strip: #{fixture['name']}" do
      report = MetroLayout.layout(trmnl, fixture, 'x-landscape')
      card = card_of(report)
      next unless card # no clock, or no room: both fine

      # the card sits inside the strip, so only the strip's own furniture can be in its way
      furniture = report['labels'].select do |label|
        !MetroLayout.class?(label, 'metro-nownext') && %w[metro-daybadge metro-wx metro-axis-note].any? { MetroLayout.class?(label, it) }
      end
      bad = furniture.select { MetroLayout.overlap(card, it) }
                     .map { "#{it['cls'][/metro-[a-z]+/] || '?'} \"#{it['text'][0, 20]}\"" }

      expect(bad).to be_empty, "the card is written over #{bad.join(', ')}"
    end

    it "a one-row card is level with the date beside it: #{fixture['name']}" do
      report = MetroLayout.layout(trmnl, fixture, 'x-landscape')
      card = card_of(report)
      next unless card

      badges = badges_of(report)
      next if badges.empty?

      # the badge this card was placed against: the nearest one to its left
      left = badges.select { it['x'] <= card['x'] + 2 }.min_by { card['x'] - it['x'] } || badges[0]
      next if card['h'] > left['h'] * 1.6 # a two-row card: centered on the band, correctly
      # ...or under the date, starting where it starts, when that row is the wider slot
      next if (card['x'] - left['x']).abs <= 4 && card['y'] >= left['y'] + left['h'] - 2

      expect((middle(card) - middle(left)).abs).to be <= [4, left['h'] * 0.35].max,
                                                   "the card sits #{(middle(card) - middle(left)).round}px off the date " \
                                                   "\"#{left['text'][0, 14]}\""
    end

    it "the card says a whole event where it has the whole strip: #{fixture['name']}" do
      report = MetroLayout.layout(trmnl, fixture, 'x-landscape')
      card = card_of(report)
      next unless card
      # only where the strip is one panel: a rolling board's today half is a narrow place
      next if badges_of(report).size > 1

      expect(card['text']).not_to include('…'), "cut on a full-width board: \"#{card['text']}\""
    end

    it "a \"now\" row is never drawn in a later day's panel: #{fixture['name']}" do
      report = MetroLayout.layout(trmnl, fixture, 'x-landscape')
      card = card_of(report)
      next unless card

      badges = badges_of(report).sort_by { it['x'] }
      next if badges.size < 2 # one panel: nowhere else to be

      now_word = fixture['metro'].dig('i18n', 'now') || 'Now'
      next unless card['text'].start_with?(now_word) # not a now row

      expect(card['x']).to be < badges[1]['x'], "a \"#{now_word}\" row sits in the panel of \"#{badges[1]['text'][0, 14]}\""
    end

    it "a card with both a now and a next keeps both rows: #{fixture['name']}" do
      metro = fixture['metro']
      now = metro['now_min']
      next if now.nil?

      events = (metro['events'] || []).select { (it['type'].to_s.empty? || it['type'] == 'event') && !it['start_min'].nil? }
      midnight = metro.dig('days', 1, 'start_min') || (24 * 60)
      on = events.any? { it['start_min'] <= now && (it['end_min'].to_i.zero? ? it['start_min'] : it['end_min']) > now }
      later = events.any? { it['start_min'] > now && it['start_min'] < midnight }
      next unless on && later

      report = MetroLayout.layout(trmnl, fixture, 'x-landscape')
      card = card_of(report)
      next unless card

      badges = badges_of(report)
      # a rolling board's today panel is half the strip and may honestly have room for one line only
      next if badges.empty? || badges.size > 1

      rows = [1, (card['h'] / badges[0]['h']).round].max
      expect(rows).to be >= 2, "both a now and a next, but the card drew #{rows} row(s): \"#{card['text'][0, 40]}\""
    end
  end
end
