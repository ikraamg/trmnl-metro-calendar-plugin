# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/order.spec.js.
RSpec.describe 'order' do
  include TransformC::Helpers

  let(:feeds) { { 'https://a.example.com/a.ics' => 'Dentist', 'https://b.example.com/b.ics' => 'Swim', 'https://c.example.com/c.ics' => 'Piano' } }
  let(:config) { JSON.generate(calendars: feeds.keys.zip(%w[Ann Ben Cy]).map { |url, name| { url:, name: } }) }

  # `slow` answers 400ms late, the rest at once
  def network(slow)
    feeds.to_h do |url, title|
      body = TransformC.ics_with_events([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: title }])
      [url, url == slow ? { body:, delay: 0.4 } : body]
    end.merge(Metro::FORECAST => { status: 503, body: '' }, Metro::I18N => { status: 404, body: '' })
  end

  def shape(slow)
    data = TransformC.payload(run_transform(now: '2026-09-09T09:00:00Z', fields: { config_json: config }, mocks: network(slow)))
    { events: data['events'].map { it.values_at('title', 'owner', 'start_min') }, legend: data['legend'].map { it.values_at('key', 'name') } }
  end

  it 'events in the same minute, and the lines, come out in the order the config names the calendars' do
    first, second, third = feeds.keys.map { shape(it) }

    expect(first[:events].map(&:first)).to eq(%w[Dentist Swim Piano]), 'the order of the config'
    expect(second).to eq(first), 'with the second feed answering last'
    expect(third).to eq(first), 'with the third feed answering last'
  end
end
