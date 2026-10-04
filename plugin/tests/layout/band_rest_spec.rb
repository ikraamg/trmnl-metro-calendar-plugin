# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/band.spec.js, the cases plugin/tests/band_spec.rb does not carry.
RSpec.describe 'band' do
  dot = "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'>" \
        "<circle cx='12' cy='12' r='6' fill='black'/></svg>"

  let(:busy) { MetroLayout.fixture('busy-day') }
  let(:five_lines) { MetroLayout.fixture('five-lines') }
  let(:sky) do
    MetroLayout.deep_copy(busy['metro']).tap do |metro|
      metro['weather'] = (metro['weather'] || []) + [
        { type: 'weather', at_min: metro['day_start_min'] + 40, icon: dot, label: 'Rain starts 06:40' },
        # just before the end of the window, where the last hour tick and the "+n more" note both live
        { type: 'weather', at_min: metro['day_end_min'] - 12, icon: dot, label: 'Rain stops 21:48' }
      ].map { MetroLayout.deep_copy(it) }
    end
  end

  define_method(:with_sky) do |metro|
    MetroLayout.deep_copy(metro).tap do |copy|
      copy['weather'] = (copy['weather'] || []) + [
        { type: 'weather', at_min: copy['day_start_min'] + 40, icon: dot, label: 'Rain stops 06:40' },
        { type: 'weather', at_min: copy['day_start_min'] + 300, icon: dot, label: 'Rain starts 13:00' },
        # a storm four minutes after the shower stops: two markers wanting one spot
        { type: 'weather', at_min: copy['day_end_min'] - 60, icon: dot, label: 'Rain stops 19:00' },
        { type: 'weather', at_min: copy['day_end_min'] - 56, icon: dot, label: 'Storms 20:00' }
      ].map { MetroLayout.deep_copy(it) }
    end
  end

  def cross(report) = report['debug']['horizontal'] ? 1 : 0

  def span_of(report, parts)
    across = cross(report)
    edges = parts.flat_map do |part|
      next part['pts'].map { it[across] } if part['pts']

      across == 1 ? [part['y'], part['y'] + part['h']] : [part['x'], part['x'] + part['w']]
    end
    edges.empty? ? [Float::INFINITY, -Float::INFINITY] : edges.minmax
  end

  def shapes(report, role) = ((report['paths'] || []) + (report['rects'] || [])).select { it['role'] == role }

  def band_of(report) = span_of(report, shapes(report, 'river'))

  def depth(report) = report['debug']['horizontal'] ? report['canvas']['h'] : report['canvas']['w']

  def scale_labels(report)
    MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-hour') || MetroLayout.class?(it, 'metro-axis-note') }
  end

  def board(metro, name) = MetroLayout.board(trmnl, metro, name)

  it 'the hour band sits at the leading edge, not through the map' do
    %w[x-landscape x-portrait og-landscape og-half].each do |name|
      report = board(busy['metro'], name)
      low, high = band_of(report)

      expect(low).to be <= 2, "#{name}: the band starts #{low.round}px in, not at the edge"
      expect(high).to be < depth(report) * 0.35,
                      "#{name}: the band reaches #{high.round}px into a #{depth(report).round}px board"
    end
  end

  it 'nothing is ruled across the board at a moment in time' do
    %w[x-landscape x-portrait].each do |name|
      report = board(sky, name)
      # the clock's own dotted rule down the board is the one exception
      nows = shapes(report, 'now')
      _low, high = band_of(report)
      across = cross(report)
      long = (report['paths'] || []).reject { nows.include?(it) }.select do |path|
        at = path['pts'].map { it[across] }
        at.max - at.min > depth(report) * 0.5 && at.min < high + 4
      end

      expect(long).to be_empty, "#{name}: #{long.size} line(s) still run from the scale across the whole board"
    end
  end

  it 'the clock is stated as a badge on the scale' do
    report = board(busy['metro'], 'x-landscape')
    # the clock's pill, not a line name's roundel (also a pill, on the map)
    pills = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-pill') && MetroLayout.class?(it, 'metro-axis-note') }

    expect(pills.size).to eq(1), "expected one clock badge on the scale, found #{pills.size}"
    expect(pills[0]['text']).to match(/\d/), "the clock badge says \"#{pills[0]['text']}\""
  end

  it 'a sky marker never lands on the hour scale' do
    %w[x-landscape og-landscape].each do |name|
      report = board(sky, name)
      markers = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-sky') }
      next if markers.empty? # too small a board to carry them at all

      bad = markers.product(scale_labels(report)).filter_map do |marker, tick|
        found = MetroLayout.overlap(marker, tick)
        "\"#{marker['text']}\" over \"#{tick['text']}\"" if found && found['w'] > 1 && found['h'] > 1
      end
      expect(bad).to be_empty, "#{name}: #{bad.size} sky marker(s) on the scale: #{bad.uniq.join('; ')}"

      # and below the strip, not floating in it; the day's forecast is set IN its strip panel on purpose (rule 2c)
      _low, high = band_of(report)
      inside = markers.select do |marker|
        !MetroLayout.class?(marker, 'metro-wx') && (cross(report) == 1 ? marker['y'] : marker['x']) < high - 1
      end
      expect(inside).to be_empty, "#{name}: #{inside.size} sky marker(s) inside the strip"
    end
  end

  it 'standing up, a sky marker crosses neither the hour strip, nor a rail, nor another marker' do
    all_bad = [[busy, 'og-half'], [five_lines, 'og-half'], [busy, 'x-portrait'], [five_lines, 'x-portrait']]
              .filter_map do |fixture, name|
      report = board(with_sky(fixture['metro']), name)
      next if report['debug']['horizontal']

      markers = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-sky') }
      rails = MetroLayout.paths_where(report, 'track') + MetroLayout.paths_where(report, 'spur')
      bad = markers.flat_map do |marker|
        on_scale = scale_labels(report).filter_map do |tick|
          found = MetroLayout.overlap(marker, tick)
          "\"#{marker['text']}\" over the scale's \"#{tick['text']}\"" if found && found['w'] > 1 && found['h'] > 1
        end
        crossed = rails.find { MetroLayout.deepest_intrusion(it['pts'], marker) > 2 }
        on_scale + (crossed ? ["\"#{marker['text']}\" across #{crossed['owner']}'s line"] : [])
      end
      bad += markers.combination(2).filter_map do |first, second|
        found = MetroLayout.overlap(first, second)
        "\"#{first['text']}\" on \"#{second['text']}\"" if found && found['w'] > 1 && found['h'] > 1
      end
      label = name == 'og-half' ? 'og-half-vertical' : name
      "#{label} (#{fixture['metro']['legend'].size} lines): #{bad.uniq.join('; ')}" if bad.any?
    end

    expect(all_bad).to be_empty, all_bad.join(' | ')
  end

  it "a line's badge is further from its rail than its name" do
    report = board(MetroLayout.fixture('all-day-every-track')['metro'], 'x-landscape')
    names = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-terminus') }
    badges = report['labels'].select { MetroLayout.class?(it, 'metro-route') }
    expect(badges).not_to be_empty, 'no badge drawn on a board with all-day states'

    tracks = MetroLayout.paths_where(report, 'track')
    bad = badges.filter_map do |badge|
      badge_middle = badge['y'] + (badge['h'] / 2.0)
      # its name: the one starting where it starts, nearest across
      name = names.select { (it['x'] - badge['x']).abs < 6 }.min_by { (it['y'] + (it['h'] / 2.0) - badge_middle).abs }
      next "\"#{badge['text']}\" has no name beside it" unless name

      name_middle = name['y'] + (name['h'] / 2.0)
      # its rail: the track nearest the name, at the name's own end
      rail = tracks.map { it['pts'][0][1] }.min_by { (it - name_middle).abs }
      next if rail.nil?
      next unless (badge_middle - rail).abs <= (name_middle - rail).abs

      "\"#{badge['text']}\" at #{badge_middle.round} is nearer the rail at #{rail.round} than \"#{name['text']}\" at #{name_middle.round}"
    end

    expect(bad).to be_empty, bad.join('; ')
  end

  it 'every line is named once, in a column at the leading edge' do
    report = board(busy['metro'], 'x-landscape')
    names = MetroLayout.text_labels(report).select { MetroLayout.class?(it, 'metro-terminus') }
    lines = (busy['metro']['legend'] || []).size - (report['debug']['dropped'] || []).size
    expect(names.size).to eq(lines), "#{names.size} name(s) for #{lines} line(s)"

    late = names.select { it['x'] > report['canvas']['w'] / 2.0 }
    expect(late).to be_empty, "#{late.size} name(s) past halfway: #{late.map { "\"#{it['text']}\" at #{it['x'].round}" }.join(', ')}"

    # ...and all starting together: a legend is read down its left edge
    edge = names.map { it['x'] }.min
    ragged = names.select { it['x'] > edge + 4 }
    expect(ragged).to be_empty, "#{ragged.size} name(s) not at the column edge #{edge.round}: " +
                                ragged.map { "\"#{it['text']}\" starts at #{it['x'].round}" }.join(', ')
  end
end
