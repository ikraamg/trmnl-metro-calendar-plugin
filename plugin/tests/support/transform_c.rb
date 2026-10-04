# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'metro'

# Shared by the specs ported from test/trmnl/transform (the transform_c folder): the input his
# baseInput built and the network his runTransform answered with.
module TransformC
  REPOSITORY = File.expand_path('../../..', __dir__)
  NOT_FOUND = { status: 404, body: '' }.freeze
  # One of the options the transform does not know, so it reads the box a device without the switch reads:
  # config_json when it holds anything, else calendar_list. His runs left the field out.
  NO_SETUP_MODE = 'json'

  module_function

  # His baseInput's custom fields, with setup_mode standing in for the field his runs left out.
  def fields(extra = {}) = { use_demo_data: 'false', setup_mode: NO_SETUP_MODE }.merge(extra)

  def variables(locale: 'en', time_zone: 'UTC') = { trmnl: { user: { locale:, time_zone_iana: time_zone } } }

  # His mocks, then ELSE_404: what he did not answer is a 404, not trmnlp's 599.
  def network(mocks = {}) = mocks.merge('*' => NOT_FOUND) { |_, given, _| given }

  def ics_with_events(events)
    text = +"BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
    events.each do |event|
      text << "BEGIN:VEVENT\r\nUID:#{event[:uid] || rand}\r\nDTSTAMP:20260101T000000Z\r\n"
      text << "RECURRENCE-ID:#{event[:recurrence_id]}\r\n" if event[:recurrence_id]
      text << "DTSTART:#{event[:start]}\r\nDTEND:#{event[:end]}\r\n"
      text << "RRULE:#{event[:rrule]}\r\n" if event[:rrule]
      text << "EXDATE:#{event[:exdate]}\r\n" if event[:exdate]
      text << "SUMMARY:#{event[:summary]}\r\n"
      text << "END:VEVENT\r\n"
    end
    text << "END:VCALENDAR\r\n"
  end

  # lib/demo.js's demoMocks: the repo's demo/ (and i18n/) files, answered from disk.
  def demo_mocks(i18n: true)
    @demo_mocks ||= {}
    @demo_mocks[i18n] ||= begin
      script = "console.log(JSON.stringify(require('./test/trmnl/lib/demo').demoMocks({ i18n: #{i18n} })))"
      JSON.parse(IO.popen(['node', '-e', script], chdir: REPOSITORY, &:read)).to_h do |mock|
        [mock['url'], mock.key?('status') ? { status: mock['status'], body: '' } : { body: mock['body'] }]
      end
    end
  end

  def repo_file(path) = File.read(File.join(REPOSITORY, path))

  # What the transform printed, as lines: his `log`.
  def printed(run)
    run.log.grep(/\Atransform std(out|err): /).flat_map { it.sub(/\Atransform std(out|err): /, '').lines }
       .map(&:chomp).reject { it.strip.empty? }
  end

  def payload(run) = run.data.fetch('data')

  def events(run) = payload(run)['events'] || []

  def urls(run) = run.requests.map { it[:url] }

  def raise_unless_ran(run)
    raise "the transform failed: #{run.error}\n#{run.log.last(5).join("\n")}" if run.error || !run.data&.key?('data')

    run
  end

  # His runTransform(...).run(baseInput(...)): a run that failed is a failed test.
  module Helpers
    def run_transform(now:, fields: {}, mocks: {}, locale: 'en', time_zone: 'UTC', state: nil)
      TransformC.raise_unless_ran(
        trmnl.transform(now:, custom_fields: TransformC.fields(fields), variables: TransformC.variables(locale:, time_zone:),
                        state:, mocks: TransformC.network(mocks))
      )
    end

    # The run and how long it took on the wall clock, trmnlp's own setup included (it does not report the
    # transform's own duration).
    def timed_transform(**)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run = run_transform(**)
      [run, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round]
    end
  end
end
