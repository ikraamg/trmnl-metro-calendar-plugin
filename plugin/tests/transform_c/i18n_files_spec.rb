# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/i18n-files.spec.js. "every i18n/<code>.json in the repo is complete and well
# formed" reads the English table inside transform.js, so it stays in the Node runner.
RSpec.describe 'i18n-files' do
  include TransformC::Helpers

  let(:now) { '2026-09-09T09:00:00Z' }
  let(:now_s) { Time.iso8601(now).to_i }
  let(:ics) { TransformC.ics_with_events([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }]) }
  # A table that no hardcoded copy could produce, so a passing assertion can only mean the fetched file was the one used.
  let(:served) { { today: 'AUJOURD-SERVED', more: '+{n} SERVED', earlier: '+{n} EARLIER-SERVED', rain_pct: '{n}% SERVED' } }
  let(:offline) { { error: :reset } }

  # The language file answers `i18n` (a body, a status, or an answer); everything else answers with the feed.
  def board(locale, i18n, state: nil)
    answer = case i18n
             when String then i18n
             when Integer then { status: i18n, body: '' }
             else i18n
             end
    config = JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }])
    run_transform(now:, fields: { use_demo_data: 'false', config_json: config }, locale:, state:,
                  mocks: { Metro::I18N => answer, '*' => ics })
  end

  def i18n_asked(run) = TransformC.urls(run).select { it.include?('/i18n/') }

  def strings(run) = TransformC.payload(run)['i18n']

  it 'the language file is fetched from this repo and is what the board reads' do
    run = board('fr-BE', JSON.generate(served))

    expect(i18n_asked(run)).to match([%r{ExcuseMi/trmnl-metro-calendar-plugin/main/i18n/fr\.json\z}]),
                               'expected one fetch of i18n/fr.json from this repo'
    expect(strings(run)['today']).to eq('AUJOURD-SERVED'), "the board did not use the downloaded table: #{strings(run)}"
  end

  it 'a half-translated file uses what it has and reads English for the rest' do
    run = board('nl-BE', JSON.generate(today: 'Vandaag-SERVED'))

    expect(strings(run)['today']).to eq('Vandaag-SERVED'), 'the translated key was ignored'
    expect(strings(run)['more']).to eq('+{n} more'), 'a missing key should fall back to English'
  end

  it 'an unreachable GitHub renders the board in English and says nothing' do
    run = board('fr-BE', offline)

    expect(strings(run)['today']).to eq('Today'), 'expected the English fallback'
    expect(TransformC.events(run)).not_to be_empty, 'a failed language fetch cost the events'
  end

  it 'a language nobody has translated yet is a 404, not a broken board' do
    run = board('pt-PT', 404)

    expect(strings(run)['today']).to eq('Today')
    expect(TransformC.events(run)).not_to be_empty, 'a missing language cost the events'
  end

  it 'the last downloaded table is cached in state and reused when the fetch fails' do
    saved = board('fr-BE', JSON.generate(served)).state
    expect(saved['i18n']).to include('lang' => 'fr'), "the table was not cached: #{saved['i18n']}"

    # an older cache, so the TTL does not simply skip the fetch
    saved['i18n']['fetchedAt'] = now_s - (24 * 3600)
    later = board('fr-BE', 500, state: saved)
    expect(strings(later)['today']).to eq('AUJOURD-SERVED'), 'a failed fetch should fall back to the cached table'
  end

  it 'a fresh cached table is used without spending the render on a fetch' do
    run = board('fr-BE', JSON.generate(served),
                state: { i18n: { lang: 'fr', strings: { today: 'CACHED' }, fetchedAt: now_s - 60 } })

    expect(strings(run)['today']).to eq('CACHED'), 'the fresh cache was not used'
    expect(i18n_asked(run)).to be_empty, 'a fresh cache should not be re-fetched'
  end

  it 'an English board fetches no language file at all' do
    run = board('en-GB', JSON.generate(served))

    expect(i18n_asked(run)).to be_empty, 'English is inline; it must not be downloaded'
    expect(strings(run)['today']).to eq('Today')
  end

  it 'a language file full of junk cannot reach the board or the state' do
    junk = { today: 'Hoi', more: { nope: 1 }, evil: '<script>', earlier: 'x' * 500 }
    run = board('nl-BE', JSON.generate(junk))

    expect(strings(run)['today']).to eq('Hoi'), 'the good key was dropped with the bad ones'
    expect(strings(run)['more']).to eq('+{n} more'), 'a non-string value reached the board'
    expect(strings(run)['earlier']).to eq('+{n} earlier'), 'a 500-character string reached the board'
    expect(run.state['i18n']['strings']).not_to have_key('evil'), 'an unknown key was stored in state'
  end

  it 'the names of the days and months come from the table, not from Intl' do
    run = board('nl-BE', TransformC.repo_file('i18n/nl.json'))
    first_day = TransformC.payload(run)['days'][0]

    expect(first_day['date_label']).to eq('Wo 9 Sep'), "the date label reads #{first_day['date_label']}"
    expect(first_day.values_at('weekday_label', 'weekday_short')).to eq(%w[Woensdag Wo]), 'the weekday reads wrong'
  end

  it 'a cached table from before a key existed is asked again after half an hour' do
    run = board('fr-BE', JSON.generate(served.merge(quiet_day: 'RUSTIG-SERVED')),
                state: { i18n: { lang: 'fr', strings: { today: 'CACHED' }, fetchedAt: now_s - (45 * 60) } })

    expect(i18n_asked(run).length).to eq(1), 'the incomplete table was not refreshed'
    expect(strings(run)['quiet_day']).to eq('RUSTIG-SERVED'), 'the refreshed key did not reach the board'
  end

  it 'a repo language file, served as-is, drives a real board' do
    french = TransformC.repo_file('i18n/fr.json')
    run = board('fr-FR', french)

    expect(strings(run)['today']).to eq(JSON.parse(french)['today']), 'expected the repo French table on the board'
  end
end
