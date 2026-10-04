# frozen_string_literal: true

require 'json'
require_relative 'metro'

# Shared by the service-alert, holidays and saved-state ports of test/trmnl/transform.
module TransformA
  I18N_DIR = File.expand_path('../../../i18n', __dir__)
  WEATHER_ICON = 'https://trmnl.com/images/plugins/weather/'
  ELSE_404 = { '*' => { status: 404 } }.freeze

  module_function

  # His cases ran with no form defaults. setup_mode 'json' reads config_json as an absent switch does, where
  # settings.yml would fill in 'links'. An absent alert_rain_threshold still arrives as 70; no case turns on it.
  def fields(extra = {}) = { use_demo_data: 'false', setup_mode: 'json' }.merge(extra)

  def variables(locale: 'en', time_zone: 'UTC') = { trmnl: { user: { locale:, time_zone_iana: time_zone } } }

  # His harness answered anything no mock named with a 404, where trmnlp answers 599.
  def mocks(table) = table.key?('*') ? table : table.merge(ELSE_404)

  # A whole-day VEVENT, the way a real holiday feed writes one: DTSTART;VALUE=DATE with an exclusive DTEND.
  def all_day_ics(entries, calendar_name = nil)
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0']
    lines << "X-WR-CALNAME:#{calendar_name}" if calendar_name
    entries.each_with_index do |entry, index|
      lines.push('BEGIN:VEVENT', "UID:hol#{index}@example", 'DTSTAMP:20260101T000000Z',
                 "DTSTART;VALUE=DATE:#{entry[:start]}")
      lines << "DTEND;VALUE=DATE:#{entry[:end]}" if entry[:end]
      lines << "RRULE:#{entry[:rrule]}" if entry[:rrule]
      lines.push("SUMMARY:#{entry[:summary]}", 'END:VEVENT')
    end
    (lines << 'END:VCALENDAR').join("\r\n") << "\r\n"
  end

  def i18n_file(lang) = File.read(File.join(I18N_DIR, "#{lang}.json"))

  def event_items(payload) = (payload['events'] || []).dup

  def titles(list) = (list || []).map { it['title'] }

  # A service alert without `parts`, which the cases about the split assert on their own.
  def without_parts(alert) = alert.is_a?(Hash) ? alert.except('parts') : alert

  def alert(kind, text, icon) = { 'kind' => kind, 'icon' => WEATHER_ICON + icon, 'text' => text }

  # Runs the transform as his runTransform(...).run(input) did: a transform that errored is a failed test.
  module Helpers
    # rubocop:disable-next Metrics/ParameterLists -- one keyword per input a case sets
    def run_transform(now:, fields:, mocks:, locale: 'en', state: nil, previous: nil)
      run = trmnl.transform(now:, custom_fields: fields, variables: TransformA.variables(locale:), state:,
                            previous_merge_variables: previous, mocks: TransformA.mocks(mocks))
      raise "the transform failed: #{run.error}\n#{run.log.last(5).join("\n")}" if run.error

      run
    end
  end
end
