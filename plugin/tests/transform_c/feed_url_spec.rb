# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/feed-url.spec.js. Its feedUrl assertions call transform.js's internal
# function directly, so they stay in the Node runner; the run is checked here.
RSpec.describe 'feed-url' do
  include TransformC::Helpers

  it 'a nextcloud public link is read from its export' do
    feed = TransformC.ics_with_events([{ start: '20260915T100000Z', end: '20260915T110000Z', summary: 'Swim' }])
    run = run_transform(now: '2026-09-15T08:00:00Z', fields: { config_json: 'https://cloud.example.com/apps/calendar/p/AbC123' },
                        mocks: { '*' => feed })
    asked = TransformC.urls(run)

    expect(asked).to include(%r{public-calendars/AbC123/\?export\z}), "fetched #{asked}"
    expect(TransformC.events(run).map { it['title'] }).to include('Swim'), 'the event did not arrive'
  end
end
