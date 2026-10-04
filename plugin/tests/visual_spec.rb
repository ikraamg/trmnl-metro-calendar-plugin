# frozen_string_literal: true

require_relative 'support/metro_layout'

# Ported from test/trmnl/visual.spec.js: the board as the panel shows it, compared pixel for pixel.
RSpec.describe 'The board as the panel shows it' do
  { 'x-landscape' => 'v2', 'og-landscape' => 'og_png' }.each do |panel, device|
    %w[busy-day five-lines].each do |name|
      it "#{name} on #{panel}" do
        screen = trmnl.render(device:, data: { data: MetroLayout.fixture(name)['metro'] }, transform: false,
                              head: MetroLayout.page['head'], wait_for: "(#{MetroLayout.page['settled']})()",
                              wait_for_timeout: 12)

        expect(screen.evaluate("(#{MetroLayout.page['report']})()")['errors']).to be_empty
        expect(screen).to fit_image_size_limit
        expect(screen).to match_snapshot("#{name}-#{panel}")
      end
    end
  end
end
