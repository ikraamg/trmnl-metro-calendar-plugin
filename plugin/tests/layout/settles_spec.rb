# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/settles.spec.js: a view reaches a final layout and stops.
RSpec.describe 'settles' do
  # every view on both panels, each the view's own template in TRMNL's real mashup slot
  sizes = { 'og' => 'og_png', 'x' => 'v2' }.flat_map do |panel, device|
    %w[full half_horizontal half_vertical quadrant].map { |view| ["#{panel}-#{view.tr('_', '-')}", { device:, view: }] }
  end

  sizes.each do |name, viewport|
    it "settles instead of redrawing forever: #{name}" do
      runs = MetroLayout.board(trmnl, MetroLayout.fixture('busy-day')['metro'], viewport)['debug']['runs']

      expect(runs).to be_a(Numeric), 'no run count reported'
      # first paint, then fonts arriving, then load; anything beyond that is the layout chasing its own tail
      expect(runs).to be <= 4, "#{name} laid out #{runs} times and was still going"
    end
  end
end
