# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/rolling.spec.js: a board that crosses a midnight names the day it crosses into.
RSpec.describe 'rolling' do
  # five in the afternoon: little left today, so the board reaches tomorrow
  let(:roll) { MetroLayout.fixture('rolling-quiet')['metro'].merge('now_min' => 17 * 60) }

  def daybreaks(report) = report['labels'].select { MetroLayout.class?(it, 'metro-daybreak') }

  def midnight_x(report)
    # the unpainted marker at the cut: the rule itself is no longer drawn
    mark = (report['rects'] || []).find { it['role'] == 'midnight-cut' }
    mark && (mark['x'] + (mark['w'] / 2.0))
  end

  it 'the second day is named on the strip, where the midnight is' do
    %w[x-landscape og-landscape].each do |name|
      report = MetroLayout.board(trmnl, roll, name)
      midnight = midnight_x(report)
      expect(midnight).not_to be_nil, "#{name}: the evening board drew no midnight"

      marks = daybreaks(report)
      expect(marks).not_to be_empty, "#{name}: no date marker at all on a two-day board"
      # it names the day the midnight OPENS, so it starts at that midnight
      expect(marks.any? { (it['x'] - midnight).abs < it['w'] + 20 }).to be(true),
                                                                       "#{name}: the date marker is at x#{marks[0]['x'].round} " \
                                                                       "and the midnight is at x#{midnight.round}"
    end
  end

  it 'a date marker has nothing written over it' do
    %w[x-landscape og-landscape og-half].each do |name|
      report = MetroLayout.board(trmnl, roll, name)
      others = MetroLayout.text_labels(report).reject { MetroLayout.class?(it, 'metro-daybreak') }
      bad = daybreaks(report).product(others).filter_map do |mark, other|
        found = MetroLayout.overlap(mark, other)
        "\"#{mark['text']}\" over \"#{other['text']}\"" if found && found['w'] > 1 && found['h'] > 1
      end

      expect(bad).to be_empty, "#{name}: #{bad.join('; ')}"
    end
  end
end
