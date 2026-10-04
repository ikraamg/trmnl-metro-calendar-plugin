# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/names.spec.js: a line's name is at the end of its line.
RSpec.describe 'names' do
  # a fifth of the board is far more slack than stepping in off an edge needs, and far less than being adrift
  slack = 0.2

  MetroLayout.fixtures.each do |fixture|
    it "every line is named at the ends of its own rail: #{fixture['name']}" do
      bad = MetroLayout::LAYOUT_VIEWPORTS.each_key.flat_map do |name|
        report = MetroLayout.layout(trmnl, fixture, name)
        flat = report['debug']['horizontal']
        span = flat ? report['canvas']['w'] : report['canvas']['h']
        next [] if span.to_f.zero?

        report['labels'].select { it['cls'].include?('metro-terminus') }.filter_map do |label|
          low, size = flat ? label.values_at('x', 'w') : label.values_at('y', 'h')
          in_from_end = [low, span - (low + size)].min
          next unless in_from_end > span * slack

          "#{name}: \"#{label['text']}\" is #{in_from_end.round}px in from either end of a #{span.round}px board"
        end
      end

      expect(bad).to be_empty, bad.first(3).join('; ')
    end
  end
end
