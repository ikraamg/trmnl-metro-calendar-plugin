# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/locale-config.spec.js.
RSpec.describe 'locale-config' do
  include TransformC::Helpers

  let(:now) { '2026-09-09T09:00:00Z' }
  # Every request answers with the feed, the language file included (which then fails to parse and the board reads
  # in English), as before.
  let(:one_event) { { '*' => TransformC.ics_with_events([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }]) } }

  def config(extra) = { config_json: JSON.generate({ calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }] }.merge(extra)),
                        use_demo_data: 'false' }

  def board(extra, at: now, mocks: one_event) = TransformC.payload(run_transform(now: at, fields: config(extra), mocks:))

  it 'a config locale overrides the account locale' do
    data = board({ locale: 'fr-FR' })

    expect(data['date_label']).to match(/sept/i), "expected a French month, got #{data['date_label']}"
  end

  it 'timeFormat 12h wins over a 24-hour locale' do
    expect(board({ locale: 'nl-BE', timeFormat: '12h' })['hour12']).to be(true), 'expected a 12-hour clock'
  end

  it 'timeFormat 24h wins over a 12-hour locale' do
    expect(board({ locale: 'en-US', timeFormat: '24h' })['hour12']).to be(false), 'expected a 24-hour clock'
  end

  it 'with no timeFormat set, the locale decides -- asked of Intl, not a region list' do
    expect(board({ locale: 'en-US' })['hour12']).to be(true), 'en-US should be a 12-hour clock'
    expect(board({ locale: 'nl-BE' })['hour12']).to be(false), 'nl-BE should be a 24-hour clock'
  end

  it 'a bare "en" account keeps a 24-hour clock' do
    expect(board({ locale: 'en' })['hour12']).to be(false), 'a bare "en" should stay on a 24-hour clock'
  end

  it 'a config timeZone decides which day is "today"' do
    feed = TransformC.ics_with_events([{ start: '20260910T090000Z', end: '20260910T100000Z', summary: 'Tomorrow in UTC' }])
    data = board({ timeZone: 'Pacific/Auckland' }, at: '2026-09-09T23:30:00Z', mocks: { '*' => feed })

    expect(data['events'].length).to eq(1), 'an event on the 10th should be today in Auckland'
  end

  it 'the demo ships US formatting with a European zone, so the override path is always live' do
    data = TransformC.payload(run_transform(now:, fields: { use_demo_data: 'true' }, mocks: TransformC.demo_mocks))

    expect(data['hour12']).to be(true), 'the demo should read on a 12-hour clock'
  end
end
