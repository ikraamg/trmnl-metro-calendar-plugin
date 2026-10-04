# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/cold.spec.js: the same board, whether or not the faces were already there.
RSpec.describe 'cold' do
  def digest(report)
    [report['debug']['gaps'], report['debug']['shed'],
     report['labels'].map { [it['cls'], it['text'], *it.values_at('x', 'y', 'w', 'h').map(&:round)] }]
  end

  { 'og_png' => 'busy-day', 'v2' => 'five-lines' }.each do |device, name|
    it "a cold page draws the board a warm one draws · #{device} · #{name}" do
      # NOTE: trmnlp has no deviceScale, so the first render is only cold when nothing drew in this Firefox before it.
      options = MetroLayout.render_options({ device: }).merge(data: { data: MetroLayout.fixture(name)['metro'] }, transform: false)
      cold = MetroLayout.checked_report(trmnl.render(**options))
      warm = MetroLayout.checked_report(trmnl.render(**options))

      expect(digest(cold)).to eq(digest(warm)), 'the first board differs from the second'
    end
  end
end
