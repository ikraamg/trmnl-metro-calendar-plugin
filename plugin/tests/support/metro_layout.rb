# frozen_string_literal: true

require 'json'

# The layout suite's fixtures and page report, read from the JavaScript the Playwright suite uses.
module MetroLayout
  REPOSITORY = File.expand_path('../../..', __dir__)
  VIEWPORTS = {
    'og-landscape' => { device: 'og_png' },
    'x-landscape' => { device: 'v2' },
    'x-portrait' => { device: 'v2', orientation: :portrait }
  }.freeze

  module_function

  def node(script) = JSON.parse(IO.popen(['node', '-e', script], chdir: REPOSITORY, &:read))

  def fixtures = @fixtures ||= node("console.log(JSON.stringify(require('./test/layout/fixtures')))")

  def fixture(name) = fixtures.find { it['name'] == name }

  def page
    @page ||= node("const p = require('./test/trmnl/lib/page'); console.log(JSON.stringify(" \
                   '{ head: p.HEAD, settled: p.settled.toString(), report: p.pageReport.toString() }))')
  end

  # The board drawn for a fixture, and the report the page gives of it.
  def report(trmnl, fixture, viewport)
    @reports ||= {}
    @reports[[fixture['name'], viewport]] ||= begin
      screen = trmnl.render(**VIEWPORTS.fetch(viewport), data: { data: fixture['metro'] }, transform: false,
                            head: page['head'], wait_for: "(#{page['settled']})()", wait_for_timeout: 12)
      screen.evaluate("(#{page['report']})()")
    end
  end
end
