# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/standing.spec.js: the standing views get the same bar as the flat ones.
RSpec.describe 'standing' do
  overlap_tolerance = 2
  intrusion_tolerance = 4

  MetroLayout.fixtures.each do |fixture|
    it "no two captions overlap standing up: #{fixture['name']}/x-portrait" do
      labels = MetroLayout.text_labels(MetroLayout.layout(trmnl, fixture, 'x-portrait'))
      bad = labels.combination(2).filter_map do |first, second|
        found = MetroLayout.overlap(first, second)
        next unless found && found['w'] > overlap_tolerance && found['h'] > overlap_tolerance

        "\"#{first['text']}\" x \"#{second['text']}\" (#{found['w'].round}x#{found['h'].round}px)"
      end

      expect(bad).to be_empty, "#{bad.size} overlapping label pair(s): #{bad.first(6).join('; ')}"
    end
  end

  MetroLayout.fixtures.each do |fixture|
    it "no rail runs through somebody else's caption standing up: #{fixture['name']}/x-portrait" do
      # standing up this catches a caption column wider than the gap between two rails
      report = MetroLayout.layout(trmnl, fixture, 'x-portrait')
      lines = MetroLayout.paths_where(report, 'track') + MetroLayout.paths_where(report, 'spur')
      owns = fixture['metro']['legend'].to_h { [it['name'], it['key']] }
      bad = MetroLayout.text_labels(report).product(lines).filter_map do |box, path|
        bare = box['text'].to_s.sub(/\s*\+\d+\z/, '')
        next if owns[bare] && owns[bare] == path['owner']

        depth = MetroLayout.deepest_intrusion(path['pts'], box)
        "\"#{box['text']}\" pierced #{depth.round}px by #{path['role']} #{path['owner']}" if depth > intrusion_tolerance
      end

      expect(bad).to be_empty, "#{bad.size} label(s) with a line through them: #{bad.first(6).join('; ')}"
    end
  end
end
