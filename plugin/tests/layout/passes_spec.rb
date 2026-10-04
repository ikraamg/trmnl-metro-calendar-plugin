# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/passes.spec.js: one board, however many times the page lays it out.
RSpec.describe 'passes' do
  def digest(report)
    debug = report['debug']
    [debug['gaps'], debug['shed'], debug['dropped'],
     report['labels'].map { [it['cls'], it['text'], *it.values_at('x', 'y', 'w', 'h').map(&:round)] }]
  end

  # the box narrowed and given back, which lays the board out twice more
  def two_more_passes(screen)
    screen.evaluate("document.querySelector('.metro-root').style.width = 'calc(100% - 7px)'")
    sleep 0.35
    screen.evaluate("document.querySelector('.metro-root').style.width = ''")
    sleep 0.3
    deadline = Time.now + 12
    sleep 0.1 until screen.evaluate("(#{MetroLayout.page['settled']})()") || Time.now > deadline
    screen.evaluate("(#{MetroLayout.page['report']})()")
  end

  def same_passes(screen)
    once = MetroLayout.checked_report(screen)
    again = two_more_passes(screen)

    expect(again['debug']['runs']).to be > once['debug']['runs'], 'the box change did not lay the board out again'
    expect(again['errors']).to eq([])
    expect(digest(again)).to eq(digest(once)), 'the board changed on another pass'
  end

  %w[og_png v2].each do |device|
    MetroLayout.fixtures.each do |fixture|
      it "the same board after more passes · #{device} · #{fixture['name']}" do
        same_passes(trmnl.render(**MetroLayout.render_options({ device: }), data: { data: fixture['metro'] }, transform: false))
      end
    end
  end

  it 'the example board that flipped is the same board after more passes' do
    same_passes(trmnl.render(**MetroLayout.render_options({ device: 'og_png', view: 'half_horizontal' }),
                             now: '2026-09-15T17:30:00Z', data: {},
                             variables: MetroLayout.trmnl_variables(time_zone: 'America/Chicago', locale: 'en-US',
                                                                    instance_name: 'Metro'),
                             custom_fields: { use_demo_data: 'true', demo_set: 'simpsons', time_format: '12h' },
                             mocks: MetroLayout.demo_mocks.merge(MetroLayout::NOT_FOUND)))
  end
end
