# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/moon.spec.js.
RSpec.describe 'moon' do
  include TransformC::Helpers

  def moon_on(date)
    config = JSON.generate(version: 1, lines: [{ name: 'Alpha' }], calendars: [{ url: 'https://x.example/a.ics', line: 'Alpha' }])
    run = run_transform(now: "#{date}T10:00:00Z", fields: { config_json: config }, mocks: { '*' => "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n" })
    (TransformC.payload(run)['days'] || []).map { it['moon'] }
  end

  it "each day carries its night's moon, lit and growing as the sky has it" do
    new_moon = moon_on('2026-09-11')
    expect(new_moon[0]).to include('illumination' => be <= 3), "the new moon: #{new_moon[0]}"
    full = moon_on('2026-09-26')
    expect(full[0]).to include('illumination' => be >= 97), "the full moon: #{full[0]}"
    waxing = moon_on('2026-09-19')
    expect(waxing[0]).to include('waxing' => true, 'illumination' => (be > 30).and(be < 80)), "a waxing moon: #{waxing[0]}"
    expect(waxing[1]).to include('illumination' => be > waxing[0]['illumination']), "tomorrow's moon is not fuller"
    waning = moon_on('2026-10-02')
    expect(waning[0]).to include('waxing' => false), "a waning moon: #{waning[0]}"
  end
end
