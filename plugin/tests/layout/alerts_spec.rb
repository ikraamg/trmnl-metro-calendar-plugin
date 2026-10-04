# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/alerts.spec.js: what the board says when a feed did not answer.
RSpec.describe 'alerts' do
  let(:busy) { MetroLayout.fixture('busy-day') }
  let(:down) { { calendars_down: ['Alex Personal'] } }

  it 'a feed that did not answer is named on the board, with a mark' do
    MetroLayout::LAYOUT_VIEWPORTS.each_key do |name|
      report = MetroLayout.layout(trmnl, busy, name, down)
      said = (report['alerts'] || []).select { it['text'].include?('Alex Personal') }

      expect(said.size).to eq(1), "#{name}: the board did not say the feed was unavailable: #{report['alerts'].to_json}"
      icon = said[0]['icon']
      expect(icon).to be_truthy, "#{name}: the line carries no mark, so it reads as a footnote"
      expect(icon['w'] > 4 && icon['h'] > 4).to be(true),
                                                "#{name}: the mark is #{icon['w'].round}x#{icon['h'].round}px, which is not a mark"
      expect(said[0]['weight'].to_f).to be >= 700,
                                        "#{name}: the warning is set at weight #{said[0]['weight']}, the same as everything else"
    end
  end

  it 'a board with nothing wrong says nothing, so the mark means something' do
    MetroLayout::LAYOUT_VIEWPORTS.each_key do |name|
      report = MetroLayout.layout(trmnl, busy, name)

      expect(report['alerts'] || []).to be_empty, "#{name}: a healthy board raised a warning: #{report['alerts'].to_json}"
    end
  end

  it 'the warning does not push the board off its own panel' do
    MetroLayout::LAYOUT_VIEWPORTS.each do |name, viewport|
      report = MetroLayout.layout(trmnl, busy, name, down)
      height = viewport[:slot] ? viewport[:slot][1] : { 'og_png' => 480, 'v2' => viewport[:orientation] ? 1872 : 1404 }[viewport[:device]]

      (report['alerts'] || []).each do |alert|
        expect(alert['y'] + alert['h']).to be <= height + 1,
                                           "#{name}: the warning reaches #{(alert['y'] + alert['h']).round}px on a #{height}px panel"
      end
    end
  end
end
