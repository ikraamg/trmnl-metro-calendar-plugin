# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/slotviews.spec.js: the other three templates, in their real mashup slots.
RSpec.describe 'slotviews' do
  slots = { 'half_horizontal' => [800, 240], 'half_vertical' => [400, 480], 'quadrant' => [400, 240] }

  let(:some) { %w[busy-day quiet-day five-lines].filter_map { MetroLayout.fixture(it) } }

  # each fixture's report, or the error its render raised
  def reports(view) = some.to_h { |fixture| [fixture['name'], attempt(fixture, view)] }

  def attempt(fixture, view)
    MetroLayout.layout(trmnl, fixture, { device: 'og_png', view: })
  rescue StandardError => e
    e
  end

  slots.each do |view, (width, height)|
    it "the view draws a board: #{view}" do
      bad = reports(view).flat_map do |name, report|
        next ["#{name}: #{report.message}"] if report.is_a?(StandardError)

        [("#{name}: no lines drawn" if report['paths'].empty?),
         ("#{name}: nothing named" if MetroLayout.text_labels(report).empty?)].compact
      end

      expect(bad).to be_empty, "#{bad.size} board(s) the view cannot draw: #{bad.join('; ')}"
    end

    it "nothing is drawn outside the slot: #{view}" do
      bad = reports(view).reject { it[1].is_a?(StandardError) }.flat_map do |name, report|
        MetroLayout.text_labels(report).select do |label|
          label['x'] < -1 || label['y'] < -1 || label['x'] + label['w'] > width + 1 || label['y'] + label['h'] > height + 1
        end.map { "#{name}: \"#{(it['text'] || '')[0, 18]}\"" }
      end

      expect(bad).to be_empty, "#{bad.size} label(s) drawn outside the slot: #{bad.first(4).join('; ')}"
    end

    it "no two names are written on each other: #{view}" do
      bad = reports(view).reject { it[1].is_a?(StandardError) }.flat_map do |name, report|
        MetroLayout.text_labels(report).combination(2).filter_map do |first, second|
          found = MetroLayout.overlap(first, second)
          next unless found && found['w'] > 2 && found['h'] > 2

          "#{name}: \"#{(first['text'] || '')[0, 14]}\" x \"#{(second['text'] || '')[0, 14]}\""
        end
      end

      expect(bad).to be_empty, "#{bad.size} overlapping name(s): #{bad.first(4).join('; ')}"
    end
  end
end
