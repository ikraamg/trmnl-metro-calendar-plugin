# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/hours.spec.js: a station for every hour of the step (rule 2n).
RSpec.describe 'hours' do
  def hour_of(text)
    if (match = /\A(\d{1,2})(?::(\d\d))?\s*(am|pm)\z/i.match(text.strip))
      (match[1].to_i % 12) + (match[3].casecmp?('pm') ? 12 : 0)
    elsif (match = /\A(\d{1,2}):00\z/.match(text.strip))
      match[1].to_i
    end
  end

  def middle(box) = box['x'] + (box['w'] / 2.0)

  def hour_labels(report)
    MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-hour') && hour_of(it['text']) }
               .map { { x: middle(it), w: it['w'], hr: hour_of(it['text']), text: it['text'] } }.sort_by { it[:x] }
  end

  def station_circles(report)
    (report['circles'] || []).select { %w[hour-station hour-station-minor].include?(it['role']) }.map { middle(it) }
  end

  %w[x-landscape og-landscape].each do |name|
    MetroLayout.fixtures.each do |fixture|
      it "every hour of the step has a station on the rail: #{fixture['name']} / #{name}" do
        report = MetroLayout.layout(trmnl, fixture, name)
        next unless report['debug']['horizontal']

        # a night hour is a star and the midnight a moon: paths, placed by the middle of their extent
        stars = (report['paths'] || []).select { it['role'] == 'hour-station-minor' && it['pts'].any? }
                                       .map { |path| path['pts'].map { it[0] }.minmax.sum / 2.0 }
        stations = (station_circles(report) + stars).sort
        # the midnight the panels change at has its station ("missing the 00:00 dot")
        bands = (report['rects'] || []).select { it['role'] == 'river' }.sort_by { it['x'] }
        if bands.size > 1
          cut = bands[1]['x']
          expect(stations).to include(be_within(3).of(cut)), "no station at the midnight (#{cut.round})"
        end

        labels = hour_labels(report)
        next if labels.size < 2

        # the hours along the strip, the day's wrap unwound
        add = 0
        labels.each_with_index do |label, index|
          add += 24 if index.positive? && label[:hr] + add <= labels[index - 1][:abs]
          label[:abs] = label[:hr] + add
        end
        step = labels.each_cons(2).reduce(0) { |gcd, (before, after)| gcd.gcd(after[:abs] - before[:abs]) }
        next if step.zero?

        # every word over its own station (a label may slide up to half its width to clear the clock)
        own = labels.map do |label|
          best = stations.each_index.min_by { (stations[it] - label[:x]).abs }
          off = best.nil? ? Float::INFINITY : (stations[best] - label[:x]).abs
          expect(off).to be <= (label[:w] / 2.0) + 3, "\"#{label[:text]}\" has no station under it"
          best
        end
        # and no stretch of the rail is bare: no two neighboring stations further apart than one step of the labels
        # at the day's fullest rate
        full = (1...labels.size).map do |index|
          (stations[own[index]] - stations[own[index - 1]]) / ((labels[index][:abs] - labels[index - 1][:abs]) / step.to_f)
        end.push(0).max
        next if full.zero?

        stations.each_cons(2) do |before, after|
          expect(after - before).to be <= full + 3,
                                    "a bare stretch of rail: #{before.round} to #{after.round}, over the #{full.round} of a full step"
        end
      end

      it "the hour words are as fine as the rail can carry: #{fixture['name']} / #{name}" do
        report = MetroLayout.layout(trmnl, fixture, name)
        next unless report['debug']['horizontal']

        labels = hour_labels(report)
        next if labels.size < 2

        stations = station_circles(report).sort
        # the clock's own pill and the midnight a panel changes at each take an hour off the words
        keep_out = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-axis-note') }
                              .map { [it['x'] - 4, it['x'] + it['w'] + 4] } +
                   (report['rects'] || []).select { it['role'] == 'river' }.map { [it['x'] - 4, it['x'] + it['w'] + 4] }
        labels.each_cons(2) do |before, after|
          # what the drawing books a word at (draw.js `room`), with a quarter again, carried across to screen px
          zoom = report['debug']['W'] ? report['canvas']['w'].to_f / report['debug']['W'] : 1
          room = 1.25 * ([after[:w], before[:w]].max + (10 * (report['debug']['S'] || 1) * zoom))
          spare = stations.select do |station|
            station - before[:x] >= room && after[:x] - station >= room && keep_out.none? { station > it[0] && station < it[1] }
          end

          expect(spare).to be_empty, "a word belonged between \"#{before[:text]}\" and \"#{after[:text]}\": " \
                                     "#{spare.size} station(s) clear of both by #{room.round}px"
        end
      end
    end
  end
end
