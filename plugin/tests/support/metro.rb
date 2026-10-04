# frozen_string_literal: true

require 'json'

# Shared by the metro specs: canned calendar feeds and the network a case runs against.
module Metro
  FORECAST = 'https://api.open-meteo.com/v1/forecast*'
  I18N = 'https://raw.githubusercontent.com/ExcuseMi/trmnl-metro-calendar-plugin/main/i18n/*'

  module_function

  def ics(events, calendar_name: nil)
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0']
    lines << "X-WR-CALNAME:#{calendar_name}" if calendar_name
    events.each_with_index do |event, index|
      lines.push('BEGIN:VEVENT', "UID:#{event[:uid] || index}", 'DTSTAMP:20260101T000000Z',
                 "DTSTART:#{event[:start]}", "DTEND:#{event[:end]}", "SUMMARY:#{event[:summary]}")
      lines << "RRULE:#{event[:rrule]}" if event[:rrule]
      lines << 'END:VEVENT'
    end
    (lines << 'END:VCALENDAR').join("\r\n") << "\r\n"
  end

  # The fields a case's board reads, with the hosted form's defaults left to settings.yml.
  def fields(extra = {})
    { use_demo_data: 'false', setup_mode: 'json', lat_lon: '51.05,3.72' }.merge(extra)
  end

  def variables(time_zone: 'UTC') = { trmnl: { user: { locale: 'en', time_zone_iana: time_zone } } }
end
