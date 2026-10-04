# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/metrics.spec.js: test/boards/metrics.json is what the page measures, on the OG and the X.
# `trmnlp test --update` rewrites it, as `trmnlp-test run metrics -u` did.
RSpec.describe 'metrics' do
  file = File.join(MetroLayout::REPOSITORY, 'test', 'boards', 'metrics.json')
  probe = MetroLayout.node("const p = require('./test/trmnl/lib/metrics-probe'); " \
                           'console.log(JSON.stringify({ classes: p.CLASSES, measure: p.measure.toString() }))')
  # a hundredth of a pixel: the advances are fractional, rounded to 1/1000
  tolerance = 0.01

  { 'og' => 'og_png', 'x' => 'v2' }.each do |dev, device|
    it "the width table is what the page measures · #{dev}" do
      screen = trmnl.render(**MetroLayout.render_options({ device: }),
                            data: { data: MetroLayout.fixture('busy-day')['metro'] }, transform: false)
      MetroLayout.checked_report(screen) # the faces are in and the board has settled
      measured = screen.evaluate("(#{probe['measure']})(#{probe['classes'].to_json})")

      if ENV[TRMNLP::Testing::Snapshot::UPDATE_ENV_KEY]
        table = File.exist?(file) ? JSON.parse(File.read(file)) : {}
        table[dev] = measured
        File.write(file, JSON.generate(table))
        next
      end

      table = JSON.parse(File.read(file))[dev] || {}
      off = []
      probe['classes'].each_key do |key|
        want = measured[key]
        have = table[key]
        next off << "#{key}: missing" unless have

        %w[h pad boxPad].each do |field|
          off << "#{key}.#{field} #{have[field]} in the table, #{want[field]} in the page" if (want[field] - have[field]).abs > tolerance
        end
        want['w'].each do |char, width|
          next unless have['w'][char].nil? || (width - have['w'][char]).abs > tolerance

          off << "#{key} #{char.to_json} #{have['w'][char]} in the table, #{width} in the page"
        end
      end
      standing = table['nameStanding']
      if !standing || (standing['h'] - measured['nameStanding']['h']).abs > tolerance
        off << "nameStanding.h #{standing&.dig('h')} in the table, #{measured['nameStanding']['h']} in the page"
      end

      expect(off.first(25)).to be_empty, "#{off.size} width(s) out of date: trmnlp test --update\n#{off.first(25).join("\n")}"
    end
  end
end
