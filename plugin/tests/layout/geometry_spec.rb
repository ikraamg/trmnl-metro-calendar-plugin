# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/geometry.spec.js: what only a real page can say about the drawing.
RSpec.describe 'geometry' do
  unpainted = ->(value) { value.nil? || value.empty? || ['none', 'rgba(0, 0, 0, 0)', 'transparent'].include?(value) }

  def off_canvas(report)
    canvas = report['canvas']
    MetroLayout.text_labels(report).select do |label|
      label['x'] < -2 || label['y'] < -2 || label['x'] + label['w'] > canvas['w'] + 2 || label['y'] + label['h'] > canvas['h'] + 2
    end
  end

  MetroLayout.fixtures.each do |fixture|
    it "fits the small panel: #{fixture['name']}" do
      report = MetroLayout.layout(trmnl, fixture, 'og-landscape')
      off = off_canvas(report)
      expect(off).to be_empty, "#{off.size} label(s) off-canvas: " + off.first(5).map { |label|
        "\"#{label['text']}\" #{label.values_at('x', 'y', 'w', 'h').map(&:round).join(',')} " \
          "in #{report['canvas']['w']}x#{report['canvas']['h']}"
      }.join(', ')

      MetroLayout.paths_where(report, 'track').each do |track|
        ys = track['pts'].map { it[1] }
        expect(ys.min >= -2 && ys.max <= report['canvas']['h'] + 2).to be(true), "track #{track['owner']} runs off the canvas"
      end
    end
  end

  MetroLayout.fixtures.each do |fixture|
    it "every label stays inside the canvas: #{fixture['name']}" do
      bad = off_canvas(MetroLayout.layout(trmnl, fixture, 'x-landscape'))

      expect(bad).to be_empty, "#{bad.size} label(s) off-canvas: #{bad.first(5).map { "\"#{it['text']}\"" }.join(', ')}"
    end
  end

  # An SVG shape with neither stroke nor fill is in the DOM, the right size, in the right place, and invisible.
  MetroLayout.fixtures.each do |fixture|
    it "everything drawn is actually visible: #{fixture['name']}" do
      report = MetroLayout.layout(trmnl, fixture, 'x-landscape')
      bad = (report['painted'] || []).filter_map do |element|
        next if element['w'].to_f.zero? && element['h'].to_f.zero? # not laid out
        # the course and the midnight cut are deliberately unpainted: facts the tests read back
        next if %w[course midnight-cut].include?(element['role'])

        # a <line> cannot be filled, and its computed fill defaults to black
        fills = !%w[line polyline].include?(element['tag'])
        inked = (!unpainted.call(element['stroke']) && element['strokeWidth'].positive?) ||
                (fills && !unpainted.call(element['fill']))
        if !inked then "#{element['role']}#{"/#{element['owner']}" if element['owner']} <#{element['tag']}>"
        elsif element['opacity'] == 0 then "#{element['role']} is fully transparent"
        end
      end

      expect(bad).to be_empty, "#{bad.size} element(s) drawn with no paint: #{bad.uniq.first(5).join('; ')}"
    end
  end

  MetroLayout.fixtures.each do |fixture|
    it "no line name lands in the river: #{fixture['name']}" do
      report = MetroLayout.layout(trmnl, fixture, 'x-landscape')
      hours = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-hour') }
      names = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-terminus') }
      bad = names.filter_map do |name|
        hour = hours.find { MetroLayout.overlap(name, it) }
        "\"#{name['text']}\" over \"#{hour['text']}\"" if hour
      end

      expect(bad).to be_empty, "#{bad.size} line name(s) in the river: #{bad.first(3).join('; ')}"
    end
  end
end
