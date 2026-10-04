# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/shipped.spec.js: the copy push.sh squeezes runs, and draws and returns what the sources do.
RSpec.describe 'shipped' do
  let(:shipped) { trmnl.plugin(MetroLayout.shipped_dir) }

  # EVERY VIEW: the squeeze rewrites all four files. On an X, with the demo day baked into .trmnlp.yml.
  %w[full half_horizontal half_vertical quadrant].each do |view|
    it "the squeezed copy lays a map out · #{view}" do
      screen = shipped.render(**MetroLayout.render_options({ device: 'v2', view: }), transform: false,
                              variables: MetroLayout.baked_variables(MetroLayout.shipped_dir))
      debug = MetroLayout.checked_report(screen)['debug']

      aggregate_failures do
        # `gaps` is one entry per line plus the two margins
        expect(debug['gaps'].size).to be >= 3, 'the map laid out with no lines on it'
        expect(debug['muddle']).to be <= 2, "#{debug['muddle']} name(s) a reader cannot pin to a mark; that is too many to ship"
      end
    end
  end

  %w[2026-09-15T12:30:00Z 2026-09-16T02:40:00Z].each do |at|
    it "the squeezed transform returns what the source returns · #{at}" do
      inputs = { now: at, variables: MetroLayout.trmnl_variables(time_zone: 'America/Chicago', locale: 'en-US'), data: {},
                 custom_fields: { use_demo_data: 'true', demo_set: 'simpsons' },
                 mocks: MetroLayout.demo_mocks.merge(MetroLayout::NOT_FOUND) }
      squeezed = shipped.transform(**inputs)
      expect(squeezed.error).to be_nil
      expect(squeezed.duration_ms).to be < 5000, 'the transform ran past the five seconds TRMNL allows'
      expect((squeezed.data.dig('data', 'legend') || []).size).to be > 0, 'the squeezed transform drew nobody'

      expect(squeezed.data).to eq(trmnl.transform(**inputs).data)
    end
  end

  # Everything the board reports about itself and everything it drew, rounded to a pixel.
  def digest(report)
    debug = report['debug'].except('ms', 'runs')
    { canvas: report['canvas'].values_at('w', 'h').map(&:round), debug:,
      labels: report['labels'].map { [it['cls'], it['text'], *it.values_at('x', 'y', 'w', 'h').map(&:round), it['timeCls']] },
      paths: report['paths'].map { [it['role'], it['owner'], it['len'].round, it['pts'].first&.map(&:round) || 0] },
      circles: report['circles'].map { [it['role'], it['owner'], it['x'].round, it['y'].round] } }
  end

  MetroLayout.fixtures.each do |fixture|
    MetroLayout::LAYOUT_VIEWPORTS.each_key do |viewport|
      it "the squeezed copy draws the board the sources draw · #{fixture['name']} · #{viewport}" do
        source = digest(MetroLayout.board(trmnl, fixture['metro'], viewport))
        squeezed = digest(MetroLayout.board(shipped, fixture['metro'], viewport, plugin: 'shipped'))

        expect(squeezed).to eq(source)
      end
    end
  end
end
