# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/clocks.spec.js: the clock under a name is one size per board.
RSpec.describe 'clocks' do
  # the stacked form only: a time set beside its name shares the name's line and is not what this is about
  def stacked(report) = report['labels'].select { !it['timeCls'].to_s.empty? && !it['timeCls'].include?('metro-inline') }

  def size_of(classes) = if classes.include?('text--base') then 'base' elsif classes.include?('text--small') then 'small' else 'other' end

  MetroLayout.fixtures.each do |fixture|
    it "every clock under the same size of name matches: #{fixture['name']}" do
      bad = MetroLayout::LAYOUT_VIEWPORTS.each_key.flat_map do |name|
        by_name = stacked(MetroLayout.layout(trmnl, fixture, name)).group_by do |label|
          if label['titleCls'].include?('text--xlarge') then 'xlarge'
          elsif label['titleCls'].include?('text--large') then 'large'
          else 'base'
          end
        end
        by_name.filter_map do |size, labels|
          kinds = labels.map { size_of(it['timeCls']) }.uniq
          "#{name}/#{size}: #{kinds.join(' and ')}" if kinds.size > 1
        end
      end

      expect(bad).to be_empty, bad.first(3).join('; ')
    end
  end

  # ...and it is actually taken: without this the rule above is satisfied by never stepping up at all
  it 'a board with room under its captions steps its clocks up' do
    seen = MetroLayout.fixtures.filter_map do |fixture|
      times = stacked(MetroLayout.layout(trmnl, fixture, 'x-landscape'))
      "#{fixture['name']}:#{size_of(times[0]['timeCls'])}" if times.any?
    end

    expect(seen).not_to be_empty, 'no board on the X drew a stacked time row at all'
    expect(seen).to include(end_with(':base')), "not one board took the step: #{seen.first(8).join(' ')}"
  end
end
