# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/faults.spec.js: the board's own verdict, on the board the page draws.
RSpec.describe 'faults' do
  MetroLayout.fixtures.each do |fixture|
    MetroLayout::LAYOUT_VIEWPORTS.each_key do |name|
      it "the drawn board knows of no fault: #{fixture['name']}/#{name}" do
        faults = MetroLayout.layout(trmnl, fixture, name)['debug']['faults']

        expect(faults).to be_empty, "#{faults.size} fault(s): #{faults.join('; ')}"
      end
    end
  end
end
