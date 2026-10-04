# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/layout/banner.spec.js: the service alert banner, the first row of the box at the map's foot.
RSpec.describe 'banner' do
  icons = 'https://trmnl.com/images/plugins/weather/'
  views = { 'og-landscape' => { device: 'og_png' }, 'og-quadrant' => { device: 'og_png', slot: [400, 240] },
            'x-landscape' => { device: 'v2' } }
  # every bit depth the badge's color is mapped for
  depths = views.merge('og-2bit' => { device: 'og_plus', palette: 'gray-4' })
  rain = { kind: 'rain', icon: "#{icons}wi-rain.svg", text: 'Rain from 14:00 until 17:00 (80%)' }
  # one of the longest lines this plugin can produce: a German snow alert out of i18n/de.json
  long = { kind: 'snow', icon: "#{icons}wi-snow.svg", text: "Schnee ab 17:00 bis in die Nacht, 80 % Wahrscheinlichkeit" }
  # the control for the wrap case: the same band, one line, same padding
  short = { kind: 'rain', icon: "#{icons}wi-rain.svg", text: 'Regen' }
  parts = rain.merge(parts: [{ t: 'Rain', s: 'b' }, { t: ' from ', s: 'q' }, { t: '14:00', s: '' },
                             { t: ' until ', s: 'q' }, { t: '17:00', s: '' }, { t: ' (80%)', s: 'q' }])
  heat = { kind: 'heat', icon: "#{icons}wi-hot.svg", text: "Hot, up to 36°C (13:00–17:00)",
           parts: [{ t: 'Hot', s: 'b' }, { t: ', up to ', s: 'q' }, { t: "36°C", s: 'b' },
                   { t: ' (', s: 'q' }, { t: "13:00–17:00)", s: '' }] }

  let(:busy) { MetroLayout.fixture('busy-day') }

  def layout(fixture, viewport, extra = nil) = MetroLayout.layout(trmnl, fixture, viewport, extra)

  def piece(report, text) = (report['banner']['pieces'] || []).find { it['text'].include?(text) } || {}

  it 'the banner prints what transform composed, unchanged' do
    views.each do |name, viewport|
      banner = layout(busy, viewport, service_alert: rain)['banner']

      expect(banner).to be_truthy, "#{name}: service_alert was set and no banner was drawn at all"
      expect(banner['text']).to eq(rain[:text]), "#{name}: the banner text"
      expect(banner['icon'] && banner['icon']['src']).to eq(rain[:icon]), "#{name}: the icon"
      expect(banner['kind']).to eq(rain[:kind]), "#{name}: data-metro-alert"
      expect(banner['icon']['x']).to be < banner['message']['x'],
                                     "#{name}: the parts are out of order: icon #{banner['icon']['x'].round}, " \
                                     "message #{banner['message']['x'].round}"
    end
  end

  it 'no alert, no banner: the element is absent, not empty' do
    views.each do |name, viewport|
      expect(layout(busy, viewport)['banner']).to be_nil, "#{name}: a board with no alert drew a banner anyway"
    end
  end

  it 'the banner sits in the box at the foot, and the map ends above it' do
    views.each do |name, viewport|
      report = layout(busy, viewport, service_alert: rain)
      banner = report['banner']
      expect(banner).to be_truthy, "#{name}: service_alert was set and no banner was drawn"
      expect(banner['y'] + banner['h']).to be <= report['canvas']['h'] + 1,
                                           "#{name}: the banner runs #{(banner['y'] + banner['h'] - report['canvas']['h']).round}px " \
                                           'off the bottom of the canvas'

      rails = (report['paths'] || []).select { %w[track spur].include?(it['role']) }
      expect(rails).not_to be_empty, "#{name}: no rails to measure against"
      rails.each do |rail|
        bottom = rail['y'] ? rail['y'] + (rail['h'] || 0) : (rail['pts'] || [[0, 0]]).map { it[1] }.max
        expect(bottom).to be <= banner['y'] + 1, "#{name}: a rail reaches #{(bottom - banner['y']).round}px into the banner"
      end
    end
  end

  it 'the banner does not push the board off its own panel' do
    %w[busy-day seven-lines full-day].each do |fixture_name|
      views.each do |name, viewport|
        report = layout(MetroLayout.fixture(fixture_name), viewport, service_alert: rain)
        # the foot gives way before a name does: a board without the band has to come out clean for it
        unless report['banner']
          expect(report['debug']['shed'].to_i.zero? && report['debug']['faults'].empty?).to be(true),
                                                                                    "#{fixture_name} #{name}: no banner was drawn, " \
                                                                                    'and the board was not the cleaner for it'
          next
        end

        panel = viewport[:slot] ? viewport[:slot].join('x') : { 'og_png' => '800x480', 'v2' => '1872x1404' }[viewport[:device]]
        view_bottom = report['view']['y'] + report['view']['h']
        over = report['root']['y'] + report['root']['h'] - view_bottom
        expect(over).to be <= 1, "#{fixture_name} #{name}: the board runs #{over.round}px past the bottom of its #{panel} panel"
        cut = report['banner']['y'] + report['banner']['h'] - view_bottom
        expect(cut).to be <= 1, "#{fixture_name} #{name}: #{cut.round}px of the banner is off the bottom of the panel"
      end
    end
  end

  it 'a banner translation that wraps to two lines still fits on the board' do
    # the quadrant's OWN view, where the framework sets its type larger and a long alert really wraps
    quadrant = { device: 'og_png', view: 'quadrant' }
    wrapped = layout(busy, quadrant, service_alert: long)
    expect(wrapped['banner']).to be_truthy, 'no banner on the quadrant'
    expect(wrapped['banner']['text']).to eq(long[:text]), 'the long banner was cut short'

    one = layout(busy, quadrant, service_alert: short)
    grew = wrapped['banner']['h'] - one['banner']['h']
    expect(grew).to be >= one['banner']['lineHeight'] * 0.8,
                    'this case is only about a banner that wraps, and this one did not: ' \
                    "#{wrapped['banner']['h'].round}px against #{one['banner']['h'].round}px for a short string. " \
                    'Pick a longer string or a narrower slot.'

    bottom = wrapped['banner']['y'] + wrapped['banner']['h']
    root_bottom = wrapped['root']['y'] + wrapped['root']['h']
    expect(bottom).to be <= root_bottom + 1, "the wrapped banner runs #{(bottom - root_bottom).round}px off the bottom of the board"
    expect(bottom).to be <= wrapped['canvas']['h'] + 1,
                      "the wrapped banner runs #{(bottom - wrapped['canvas']['h']).round}px off the bottom of the canvas"
  end

  it "the weather's own name is the loud one, on every bit depth" do
    depths.each do |name, viewport|
      report = layout(busy, viewport, service_alert: parts)
      thing = piece(report, 'Rain')
      around = piece(report, 'from')

      expect(thing['weight'].to_f).to be > around['weight'].to_f,
                                      "#{name}: the thing itself is not heavier than the words around it: " \
                                      "#{thing['weight']} vs #{around['weight']}"
      expect(thing['color']).to eq(report['banner']['paper']),
                                "#{name}: the thing is #{thing['color']} on a band whose paper is #{report['banner']['paper']}"
      expect(around['color']).not_to eq(report['banner']['paper']),
                                     "#{name}: the words around it are the same color, so there is no hierarchy at all"
    end
  end

  it "the banner icon is drawn in the band's paper, a shade larger than the words" do
    views.each do |name, viewport|
      banner = layout(busy, viewport, service_alert: rain)['banner']
      expect(banner && banner['icon']).to be_truthy, "#{name}: no icon on the banner"

      icon = banner['icon']
      size = banner['message']['fontSize']
      expect(icon['w'] >= size && icon['h'] >= size).to be(true),
                                                       "#{name}: the icon is #{icon['w'].round}px, smaller than the #{size}px words beside it"
      expect(icon['mask']).to match(/wi-rain\.svg/), "#{name}: the icon is not masked, so it is not recolored: #{icon['mask']}"
      expect(icon['bg']).to eq(banner['paper']), "#{name}: the icon is painted #{icon['bg']} on the #{banner['ink']} band"
      expect(banner['message']['color']).to eq(banner['paper']), "#{name}: the message should be in the band's paper"
      expect(icon['h']).to be > size, "#{name}: the icon (#{icon['h'].round}px) is not set above the #{size}px words it introduces"
      expect(banner['radius']).to be > 0, "#{name}: the band has square corners"
    end
  end

  it 'solid ink, paper text: the banner reads as an interruption' do
    views.each do |name, viewport|
      report = layout(busy, viewport, service_alert: rain)
      banner = report['banner']
      expect(banner).to be_truthy, "#{name}: service_alert was set and no banner was drawn"

      expect(banner['ink']).not_to eq(banner['paper']),
                                   "#{name}: the banner is #{banner['paper']} text on a #{banner['ink']} band, which is invisible"
      expect(banner['paper']).to eq(report['boardBg']),
                                 "#{name}: the banner text should be knocked out of the band in the canvas color (#{report['boardBg']})"
      expect(banner['ink']).not_to eq(report['boardBg']), "#{name}: the band is the same color as the board, so it is not a band"
    end
  end

  it 'the banner sets the thing bold and the clock quiet' do
    report = layout(busy, views['x-landscape'], service_alert: parts)
    pieces = report['banner']['pieces'] || []
    expect(report['banner']['text']).to eq(parts[:text]), 'the pieces must still read as the line'
    expect(pieces.size).to be > 1, "the banner was printed as one piece: #{pieces.to_json}"

    expect(piece(report, 'Rain')['weight'].to_f).to be > piece(report, 'from')['weight'].to_f,
                                                    'the thing itself is not bolder than the words around it: ' \
                                                    "#{piece(report, 'Rain')['weight']} vs #{piece(report, 'from')['weight']}"
    clock = pieces.find { it['text'].include?('14:00') }
    body = pieces.find { it['text'].include?('from') }
    expect(clock && body && clock['color'] != body['color']).to be(true),
                                                               "the clock is the same color as the words: #{[clock, body].to_json}"
  end

  it 'a heat banner bolds the weather and its degree, and lights the stretch' do
    report = layout(busy, views['x-landscape'], service_alert: heat)
    expect(report['banner']['text']).to eq(heat[:text]), 'the pieces must still read as the line'

    expect(piece(report, '36')['weight'].to_f).to be > piece(report, 'up to')['weight'].to_f,
                                                  'the temperature is not bolder than the words around it: ' \
                                                  "#{piece(report, '36')['weight']} vs #{piece(report, 'up to')['weight']}"
    expect(piece(report, '13:00')['color']).not_to eq(piece(report, 'up to')['color']),
                                                   "the stretch is the same color as the words holding it: #{report['banner']['pieces'].to_json}"
  end

  it 'a banner with no parts still prints its whole line' do
    report = layout(busy, views['x-landscape'], service_alert: rain)

    expect(report['banner']['text']).to eq(rain[:text]), 'the fallback dropped the sentence'
  end
end
