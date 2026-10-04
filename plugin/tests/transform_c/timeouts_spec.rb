# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/timeouts.spec.js.
RSpec.describe 'timeouts' do
  include TransformC::Helpers

  let(:now) { '2026-09-09T09:00:00Z' }
  let(:a) { 'https://a.example.com/a.ics' }
  let(:b) { 'https://b.example.com/b.ics' }

  def ics_text(title) = TransformC.ics_with_events([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: title }])

  def two_calendars(extra = {})
    config = JSON.generate(lines: [{ name: 'Alex' }, { name: 'Sam' }],
                           calendars: [{ url: a, name: 'Alex', rules: [{ match: { type: 'any' }, line: 'Alex' }] },
                                       { url: b, name: 'Sam', rules: [{ match: { type: 'any' }, line: 'Sam' }] }])
    { use_demo_data: 'false', config_json: config }.merge(extra)
  end

  it 'every fetch carries an abort signal, so nothing can hang for ever' do
    run = run_transform(now:, fields: two_calendars(lat_lon: '51.05,3.72'), locale: 'fr-BE', # pulls in the language file too
                        mocks: { '*' => { body: ics_text('Afternoon'), delay: 10 } })
    asked = run.requests

    expect(asked.length).to be >= 4, "expected the language file, the forecast and both feeds, saw #{asked.length}"
    expect(asked).to all(include(aborted: true)), 'not given up, so no abort signal'
  end

  it 'one dead feed costs its own line, not the board' do
    run = run_transform(now:, fields: two_calendars, mocks: { a => { status: 404, body: '' }, '*' => ics_text('Sam Time') })
    titles = TransformC.events(run).map { it['title'] }

    expect(titles).to include('Sam Time'), "the healthy feed was lost with the dead one: #{titles.join(', ')}"
  end

  it 'a feed that eats the whole deadline does not get to spend the next one' do
    demo_config = 'https://raw.githubusercontent.com/ExcuseMi/trmnl-metro-calendar-plugin/main/demo/*/config.json'
    config = JSON.generate(calendars: [{ url: a, name: 'Alex' }, { url: b, name: 'Sam' }])
    run = run_transform(now:, fields: { use_demo_data: 'true' },
                        mocks: { demo_config => { body: config, advance_clock: 5 }, '*' => ics_text('Sam Time') })
    calls = TransformC.urls(run)

    expect(calls).to include(a_string_ending_with('/config.json')), "the demo config was never asked for: #{calls.join(', ')}"
    expect(calls & [a, b]).to be_empty, "a feed was fetched with no budget left: #{calls.join(', ')}"
    expect(run.data).not_to be_nil, 'the render should still produce a board'
  end

  it 'a slow forecast does not hold the feeds back: they are all asked for at once' do
    run = run_transform(now:, fields: two_calendars(lat_lon: '51.05,3.72'),
                        mocks: { Metro::FORECAST => { status: 503, body: '', delay: 4 }, a => ics_text('Alex Time'), b => ics_text('Sam Time') })
    calls = TransformC.urls(run)
    titles = TransformC.events(run).map { it['title'] }.sort

    expect(calls.grep(/\.ics\z/).length).to eq(2), "the feeds waited for the forecast: #{calls.join(', ')}"
    expect(titles.join(',')).to eq('Alex Time,Sam Time'), "the feeds lost their events to the forecast: #{titles.join(', ')}"
  end

  it 'a feed that answers at once and then sends its body slowly is cut at the deadline' do
    run = run_transform(now:, fields: two_calendars,
                        mocks: { Metro::FORECAST => { status: 503, body: '' }, a => { body: ics_text('Alex Time'), delay: 2 },
                                 b => { body: ics_text('Sam Time'), body_delay: 60 } })
    titles = TransformC.events(run).map { it['title'] }

    expect(run.duration_ms).to be < 3800, "the render waited on a body that never came: #{run.duration_ms}ms"
    expect(titles).to include('Alex Time'), "the feed that answered was lost: #{titles.join(', ')}"
  end
end
