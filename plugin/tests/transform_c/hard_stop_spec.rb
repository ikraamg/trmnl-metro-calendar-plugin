# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/hard-stop.spec.js.
RSpec.describe 'hard-stop' do
  include TransformC::Helpers

  it 'a feed that never answers, abort or no abort, costs the budget and no more' do
    run, took = timed_transform(now: '2026-09-19T10:00:00Z',
                                fields: { calendar_list: 'Alpha https://x.example/a.ics', setup_mode: 'links',
                                          news_feeds: 'https://x.example/news.xml' },
                                mocks: { '*' => { body: '', delay: 60 } })

    expect(took).to be < 3800, "the render took #{took}ms"
    expect(run.data).to include('data'), 'no board'
  end
end
