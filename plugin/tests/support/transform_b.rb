# frozen_string_literal: true

require 'json'
require_relative 'metro'

# Shared by the specs ported from test/trmnl/transform/{rules,rolling,multi-day,demo-config,rule-fields,
# settings-yml,one-event}.spec.js: his icsWithEvents, baseInput and ELSE_404, on `trmnl.transform`.
module TransformB
  REPO = File.expand_path('../../..', __dir__)
  DEMO_DIR = File.join(REPO, 'demo')
  DEMO_BASE = 'https://raw.githubusercontent.com/ExcuseMi/trmnl-metro-calendar-plugin/main/'
  DAY = 24 * 60

  module_function

  # His icsWithEvents, line for line (LOCATION is written twice there too).
  def ics(events)
    out = +"BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
    events.each do |event|
      out << "BEGIN:VEVENT\r\nUID:#{event[:uid] || rand}\r\nDTSTAMP:20260101T000000Z\r\n"
      out << "RECURRENCE-ID:#{event[:recurrence_id]}\r\n" if event[:recurrence_id]
      out << "DTSTART:#{event[:start]}\r\nDTEND:#{event[:end]}\r\n"
      out << "RRULE:#{event[:rrule]}\r\n" if event[:rrule]
      out << "EXDATE:#{event[:exdate]}\r\n" if event[:exdate]
      out << "SUMMARY:#{event[:summary]}\r\n"
      out << "DESCRIPTION:#{event[:description]}\r\n" if event[:description]
      out << "LOCATION:#{event[:location]}\r\n" if event[:location]
      out << "CATEGORIES:#{event[:categories]}\r\n" if event[:categories]
      out << "STATUS:#{event[:status]}\r\n" if event[:status]
      out << "LOCATION:#{event[:location]}\r\n" if event[:location]
      out << "END:VEVENT\r\n"
    end
    out << "END:VCALENDAR\r\n"
  end

  # His baseInput's custom fields. `setup_mode` is set to a value the transform does not know, which reads
  # as "no answer" the way his fieldDefaults:false input did; TRMNL's default ('links') would ignore config_json.
  def fields(extra = {}) = { use_demo_data: 'false', setup_mode: 'json' }.merge(extra)

  # His ELSE_404, appended unless the case already answers everything.
  def network(mocks) = mocks.key?('*') ? mocks : mocks.merge('*' => { status: 404 })

  # His demoMocks(): every file under demo/ and i18n/, answered from disk at its raw.githubusercontent URL.
  def demo_mocks
    files = %w[demo i18n].flat_map do |dir|
      Dir.glob('**/*', base: File.join(REPO, dir)).map { |rel| "#{dir}/#{rel}" }
    end
    files.select { File.file?(File.join(REPO, it)) }.sort.to_h { [DEMO_BASE + it, File.read(File.join(REPO, it))] }
  end
end

# runTransform(...).run(baseInput(...)), included per describe: a run that errored fails the example.
module TransformBHelpers
  def board_run(now:, fields: {}, mocks: {}, time_zone: 'UTC')
    run = trmnl.transform(now:, custom_fields: TransformB.fields(fields), variables: Metro.variables(time_zone:),
                          mocks: TransformB.network(mocks))
    raise "the transform failed: #{run.error}\n#{run.log.last(20).join("\n")}" if run.error || !run.data&.key?('data')

    run
  end

  def board(...) = board_run(...).data['data']

  def config(json) = { config_json: JSON.generate(json) }
end
