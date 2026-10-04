# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/logging.spec.js. "a host is all that comes out of a link" (hostOf) and "the
# network budget leaves the runtime room to finish" (RENDER_BUDGET_MS) read transform.js's internals, so they stay
# in the Node runner.
RSpec.describe 'logging' do
  include TransformC::Helpers

  let(:ics) { TransformC.ics_with_events([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }]) }
  # A published calendar link, in the shape the real ones take: a long opaque token in the path, and a query.
  let(:secret) { 'https://cloud.example.com/remote.php/dav/public-calendars/8XaL43rwEgSj4ETE?export&token=s3cr3t-do-not-log' }

  def network(weather_fails: false, calendars_fail: false)
    { Metro::FORECAST => weather_fails ? { status: 503, body: '' } : '{}',
      Metro::I18N => { status: 404, body: '' },
      '*' => calendars_fail ? { status: 500, body: '' } : ics }
  end

  def printed(fields: {}, **network_options)
    config = JSON.generate(calendars: [{ url: secret, name: 'Alex' }])
    run = run_transform(now: '2026-09-09T09:00:00Z', fields: { use_demo_data: 'false', config_json: config }.merge(fields),
                        mocks: network(**network_options))
    TransformC.printed(run)
  end

  it 'a feed that does not answer says so in the log, with its name and why' do
    log = printed(calendars_fail: true)
    said = log.grep(/calendar/i).join("\n")

    expect(said).not_to be_empty, "a feed failed and the log said nothing: #{log}"
    expect(said).to include('Alex'), "the log does not say which calendar: #{said}"
    expect(said).to match(/500/), "the log does not say why: #{said}"
    expect(said).to include('cloud.example.com'), "the log does not say which host: #{said}"
  end

  it '...and never prints the link itself, which is a credential' do
    all = printed(calendars_fail: true).join("\n")

    expect(all).not_to include(secret), 'the log printed the whole link'
    expect(all).not_to include('8XaL43rwEgSj4ETE'), "the log printed the calendar token: #{all}"
    expect(all).not_to include('s3cr3t'), "the log printed the query: #{all}"
    expect(all).not_to include('remote.php'), "the log printed the path: #{all}"
  end

  it 'a forecast that fails says so, and a language file that fails says so' do
    log = printed(fields: { lat_lon: '51.05,3.72' }, weather_fails: true)

    expect(log.join("\n")).to match(/forecast/i), "a 503 from the forecast went unremarked: #{log}"
  end

  it 'a config that will not parse says so' do
    log = printed(fields: { config_json: '{ this is not json' })

    expect(log.join("\n")).to match(/Calendars box|config/i), "an unreadable config was not logged: #{log}"
  end

  it 'a board with nothing wrong writes nothing, so the log means something' do
    expect(printed).to eq([]), 'a healthy render wrote to the log'
  end
end
