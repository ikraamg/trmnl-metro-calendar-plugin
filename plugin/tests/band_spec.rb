# frozen_string_literal: true

require_relative 'support/metro_layout'

# Ported from test/trmnl/layout/band.spec.js.
RSpec.describe 'Hour band' do
  def shapes(report, role) = (report['paths'] || []).concat(report['rects'] || []).select { it['role'] == role }

  def band(report)
    across = report.dig('debug', 'horizontal') ? 1 : 0
    edges = shapes(report, 'river').flat_map do |shape|
      next shape['pts'].map { it[across] } if shape['pts']

      across == 1 ? [shape['y'], shape['y'] + shape['h']] : [shape['x'], shape['x'] + shape['w']]
    end
    edges.minmax
  end

  MetroLayout.fixtures.each do |fixture|
    it "keeps every line out of the hour band: #{fixture['name']}" do
      report = MetroLayout.report(trmnl, fixture, 'x-landscape')
      _top, bottom = band(report)
      crossing = (report['paths'] || []).select { %w[track spur].include?(it['role']) }
                                        .select { |path| path['pts'].any? { it[1] < bottom - 1 } }

      expect(crossing.map { "#{it['role']} #{it['owner']}" }.uniq).to be_empty
    end
  end

  it 'writes the hours on the band' do
    report = MetroLayout.report(trmnl, MetroLayout.fixture('busy-day'), 'x-landscape')
    top, bottom = band(report)
    hours = report['labels'].select { " #{it['cls']} ".include?(' metro-hour ') }

    expect([hours.size >= 3, hours.reject { it['y'] >= top - 2 && it['y'] + it['h'] <= bottom + 2 }]).to eq([true, []])
  end
end
