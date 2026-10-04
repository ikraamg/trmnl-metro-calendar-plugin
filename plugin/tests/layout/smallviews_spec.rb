# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/smallviews.spec.js: halves and quadrants, the full template in a slot.
RSpec.describe 'smallviews' do
  # a slot is given in the screen's OWN css px, which for the X is 1040x780
  slots = { 'og-quadrant' => { device: 'og_png', slot: [400, 240] },
            'og-half-horizontal' => { device: 'og_png', slot: [800, 240] },
            'og-half-vertical' => { device: 'og_png', slot: [400, 480] } }
  x_slots = { 'x-quadrant' => { device: 'v2', slot: [520, 390] },
              'x-half-horizontal' => { device: 'v2', slot: [1040, 390] },
              'x-half-vertical' => { device: 'v2', slot: [520, 780] } }

  let(:busy) { MetroLayout.fixture('busy-day') }
  let(:early) do
    # events before 10:00 become "+n earlier", and the clock sits at the very head
    MetroLayout.deep_copy(busy['metro']).merge('day_start_min' => 600, 'now_min' => 605)
  end

  def board(metro, viewport) = MetroLayout.board(trmnl, metro, viewport)

  def axis_notes(report) = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-axis-note') }

  it 'a tiny view spends no height on a header that says nothing' do
    slots.first(2).concat(x_slots.first(2)).each do |name, viewport|
      report = board(busy['metro'], viewport)
      # in css px, the units a slot is given in: the debug dump's own W/H
      laid_height = report['debug']['H'] || report['canvas']['h']
      zoom = report['debug']['Z'] || 1
      top = (MetroLayout.text_labels(report).map { it['y'] }.min || Float::INFINITY) / zoom.to_f
      slot_height = viewport[:slot][1]

      expect(laid_height).to be >= slot_height * 0.9,
                             "#{name}: the canvas is only #{laid_height.round}px of a #{slot_height}px slot, " \
                             'so something above it is still taking the height'
      expect(top).to be < slot_height * 0.2, "#{name}: the topmost thing drawn starts #{top.round}px down a #{slot_height}px slot"
    end
  end

  it 'a flat slot draws as many people as it can hold, not as few' do
    report = board(busy['metro'], slots['og-half-horizontal'])
    lines = (busy['metro']['legend'] || []).size - (report['debug']['dropped'] || []).size

    expect(lines).to be >= 2, "og-half-horizontal drew #{lines} line(s) of 4; the tight estimate says two fit"
  end

  it 'a slot keeps only the people whose captions it can write legibly' do
    five = MetroLayout.fixture('five-lines')
    [[busy, 'og-half-vertical', slots, 5], [five, 'og-half-vertical', slots, 3],
     [five, 'x-half-vertical', x_slots, 4], [five, 'x-quadrant', x_slots, 3]].each do |fixture, name, table, most|
      count = MetroLayout.text_labels(board(fixture['metro'], table[name])).combination(2).count do |first, second|
        found = MetroLayout.overlap(first, second)
        found && found['w'] > 2 && found['h'] > 2
      end

      expect(count).to be <= most, "#{name} (#{fixture['name']}): #{count} overlapping caption pairs, " \
                                   'so it is keeping more people than it can write down'
    end
  end

  it 'the clock badge never lands on the overflow note' do
    slots.each do |name, viewport|
      bad = axis_notes(board(early, viewport)).combination(2).filter_map do |first, second|
        found = MetroLayout.overlap(first, second)
        "\"#{first['text']}\" over \"#{second['text']}\"" if found && found['w'] > 1 && found['h'] > 1
      end

      expect(bad).to be_empty, "#{name}: #{bad.join('; ')}"
    end
  end

  it 'an overflow note that cannot fit its word keeps its number' do
    report = board(early, slots['og-quadrant'])
    counts = axis_notes(report).select { it['text'].match?(/\A\+\d/) }
    expect(counts).not_to be_empty, 'a board with events off both ends of the window drew no overflow note at all'

    counts.each do |note|
      expect(note['x'] + note['w'] <= report['canvas']['w'] + 1 && note['x'] >= -1).to be(true),
                                                                                      "the note \"#{note['text']}\" runs off the scale"
    end
  end
end
