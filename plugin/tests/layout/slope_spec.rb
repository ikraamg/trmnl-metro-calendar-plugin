# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/slope.spec.js: nothing on tomorrow's panel stands under the slope (rule 2l).
RSpec.describe 'slope' do
  %w[x-landscape og-landscape].each do |name|
    MetroLayout.fixtures.select { (it['metro']['days'] || []).size > 1 }.each do |fixture|
      it "tomorrow's words clear the slope: #{fixture['name']} / #{name}" do
        report = MetroLayout.layout(trmnl, fixture, name)
        next unless report['debug']['horizontal']

        bands = (report['rects'] || []).select { it['role'] == 'river' }.sort_by { it['x'] }
        next if bands.size < 2

        scale = report['debug']['S'] || 1
        cut = bands[1]['x']
        strip_end = bands[0]['y'] + bands[0]['h']
        slant_max = [bands[0]['h'], (bands[1]['w'] * 0.4).floor].min
        next if slant_max < 8 * scale

        bad = report['labels'].select do |label|
          next false unless label['cls'].match?(/metro-daybadge|metro-wx|metro-hour|metro-axis-note/)
          next false if label['y'] + label['h'] > strip_end + 1 || label['x'] + (label['w'] / 2.0) < cut

          reach = [slant_max, [0, strip_end - label['y'] - (2 * scale)].max].min
          label['x'] < cut + reach - 2
        end

        expect(bad).to be_empty, bad.map { |label|
          under = cut + [slant_max, strip_end - label['y'] - (2 * scale)].min - label['x']
          "\"#{label['text']}\" starts #{under.round}px under the slope"
        }.join('; ')
      end
    end
  end
end
