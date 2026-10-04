# frozen_string_literal: true

require 'digest'
require 'json'
require 'yaml'
require_relative 'metro_layout'

# The rest of the layout suite's harness (test/trmnl/lib/layout.js, page.js, demo.js and shipped.js): any viewport,
# a mashup slot, extra payload keys, the checked report, the demo's mocks, the squeezed copy, and the geometry
# helpers the cases share.
module MetroLayout
  # his VIEWPORTS: og-half is the FULL template in a 400x480 slot of the 800x480 screen
  LAYOUT_VIEWPORTS = VIEWPORTS.merge('og-half' => { device: 'og_png', slot: [400, 480] }).freeze
  DEMO_BASE = 'https://raw.githubusercontent.com/ExcuseMi/trmnl-metro-calendar-plugin/main/'
  NOT_FOUND = { '*' => { status: 404, body: '' } }.freeze
  LABEL_CLASSES = %w[metro-label metro-terminus metro-hour metro-sky metro-axis-note].freeze

  module_function

  def layout_viewport(viewport) = viewport.is_a?(String) ? LAYOUT_VIEWPORTS.fetch(viewport) : viewport

  # trmnlp-test's slotSize: a view's box comes from --full-w/--full-h, so overriding them gives the full view a slot.
  def slot_style(slot) = "<style>.screen{--full-w:#{slot[0]}px !important;--full-h:#{slot[1]}px !important}</style>"

  # A viewport ({ device:, view:, orientation:, palette:, slot: [w, h] }) as trmnlp render options, with his page.
  def render_options(viewport)
    viewport = layout_viewport(viewport)
    slot = viewport[:slot] if viewport.fetch(:view, 'full') == 'full'
    viewport.slice(:device, :view, :orientation, :palette)
            .merge(head: page['head'] + (slot ? slot_style(slot) : ''), wait_for: "(#{page['settled']})()",
                   wait_for_timeout: 12)
  end

  # His report(): a thrown layout, a missing canvas or a board that never published its record is an error.
  def checked_report(screen)
    report = screen.evaluate("(#{page['report']})()")
    raise "the page has no #{report['missing']} (did the template render?)" if report['missing']
    raise "the layout threw: #{report['errors'].join(' | ')}" if report['errors']&.any?
    raise "the solver threw while laying the board out: #{report['metroError']}" if report['metroError']
    raise 'the layout never published data-metro-debug' unless report['debug']
    raise "the page had problems: #{screen.problems.join(' | ')}" if screen.problems.any?

    report
  end

  # His render(metro, viewport, extra): the payload (with extra keys merged in) drawn on a viewport, memoized.
  def board(trmnl, metro, viewport, extra = nil, plugin: 'source')
    data = extra ? metro.merge(JSON.parse(JSON.generate(extra))) : metro
    key = Digest::SHA1.hexdigest(JSON.generate([data, layout_viewport(viewport), plugin]))
    @boards ||= {}
    @boards[key] ||= checked_report(trmnl.render(**render_options(viewport), data: { data: }, transform: false))
  end

  def layout(trmnl, fixture, viewport, extra = nil) = board(trmnl, fixture['metro'], viewport, extra)

  def deep_copy(value) = JSON.parse(JSON.generate(value))

  # ---------------------------------------------------------------- geometry

  def inflate(rect, by) = { 'x' => rect['x'] - by, 'y' => rect['y'] - by, 'w' => rect['w'] + (2 * by), 'h' => rect['h'] + (2 * by) }

  def overlap(first, second)
    across = [first['x'] + first['w'], second['x'] + second['w']].min - [first['x'], second['x']].max
    down = [first['y'] + first['h'], second['y'] + second['h']].min - [first['y'], second['y']].max
    across.positive? && down.positive? ? { 'w' => across, 'h' => down, 'area' => across * down } : nil
  end

  def point_in?(point, rect)
    point[0].between?(rect['x'], rect['x'] + rect['w']) && point[1].between?(rect['y'], rect['y'] + rect['h'])
  end

  def class?(label, name) = " #{label['cls']} ".include?(" #{name} ")

  # the text boxes a reader is meant to read: captions, terminus names, hour ticks and the sky band
  def text_labels(report) = report['labels'].select { |label| LABEL_CLASSES.any? { class?(label, it) } }

  def paths_where(report, role) = report['paths'].select { it['role'] == role }

  # how far a path strays inside a box, in px; 0 when it never enters it
  def deepest_intrusion(points, box)
    points.select { point_in?(it, box) }.map do |point|
      [point[0] - box['x'], box['x'] + box['w'] - point[0], point[1] - box['y'], box['y'] + box['h'] - point[1]].min
    end.max || 0
  end

  # ---------------------------------------------------------------- the demo and the squeezed copy

  # His demoMocks: the demo's files and the languages, answered from the repo; `missing` withholds files.
  def demo_mocks(missing: [], i18n: true)
    dirs = ['demo'] + (i18n ? ['i18n'] : [])
    files = dirs.flat_map { |dir| Dir.glob("#{dir}/**/*", base: REPOSITORY).sort }
                .reject { File.directory?(File.join(REPOSITORY, it)) }
    files.to_h do |rel|
      [DEMO_BASE + rel, missing.include?(rel) ? { status: 404, body: '' } : File.read(File.join(REPOSITORY, rel))]
    end
  end

  # trmnlp-test's timeZone:, locale: and instanceName:, as the trmnl variables they become.
  def trmnl_variables(time_zone: nil, locale: nil, instance_name: nil)
    user = { time_zone_iana: time_zone, locale: }.compact
    { trmnl: { user:, plugin_settings: { instance_name: }.compact } }
  end

  # The copy push.sh uploads, built by his lib/shipped.js; an absolute directory.
  def shipped_dir
    @shipped_dir ||= File.join(REPOSITORY, IO.popen(['node', '-e', "process.stdout.write(require('./test/trmnl/lib/shipped').shippedPlugin())"],
                                                    chdir: REPOSITORY, &:read))
  end

  # trmnl for another copy of the plugin (trmnlp-test's trmnl.plugin(dir)), drawing in the example's browser.

  # The demo day .trmnlp.yml bakes into a plugin's variables (trmnlp replaces them with a test's own).
  def baked_variables(dir) = YAML.load_file(File.join(dir, '.trmnlp.yml'))['variables']
end
