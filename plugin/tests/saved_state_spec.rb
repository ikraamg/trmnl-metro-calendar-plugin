# frozen_string_literal: true

require_relative 'support/metro'
require_relative 'support/transform_a'

# Ported from test/trmnl/transform/saved-state.spec.js.
RSpec.describe 'Saved state' do
  include TransformA::Helpers

  let(:now) { '2026-09-09T09:00:00Z' }
  let(:ics_url) { 'https://cloud.example.com/cal-2.ics' }
  let(:feed) do
    Metro.ics([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }], calendar_name: 'Alex Personal')
  end
  let(:forecast) do
    { daily: { temperature_2m_max: [21], temperature_2m_min: [12], precipitation_probability_max: [40],
               weathercode: [61], sunrise: ['2026-09-09T07:05'], sunset: ['2026-09-09T19:45'] },
      hourly: { time: %w[2026-09-09T13:00 2026-09-09T14:00], precipitation_probability: [80, 10] } }
  end
  let(:fields) { Metro.fields(config_json: JSON.generate(calendars: [{ url: ics_url }])) }

  def network(weather_fails: false, calendars_fail: false)
    { Metro::FORECAST => weather_fails ? { status: 503 } : { json: forecast },
      Metro::I18N => { status: 404 },
      '*' => calendars_fail ? { status: 500 } : feed }
  end

  def transform(state: nil, **network_options)
    trmnl.transform(now:, custom_fields: fields, variables: Metro.variables, state:, mocks: network(**network_options))
  end

  it 'hands saved state back to the runtime, not just the board' do
    run = transform
    expect([run.error, run.state.class, run.data.key?('data')]).to eq([nil, Hash, true])
  end

  it 'keeps the last good forecast and replays it when the weather API fails' do
    good = transform
    later = transform(state: good.state, weather_fails: true)

    expect(later.data.dig('data', 'header_weather', 'hi')).to eq(good.data.dig('data', 'header_weather', 'hi'))
  end

  it 'replays the forecast markers too, without a sun' do
    later = transform(state: transform.state, weather_fails: true)
    marks = later.data.dig('data', 'weather')

    expect(marks).to(be_any.and(all(include('type' => 'weather'))))
  end

  # ------------------------------------------------- the rest of saved-state.spec.js

  let(:now_s) { Time.iso8601(now).to_i }

  def board(state: nil, previous: nil, extra: {}, **network_options)
    run_transform(now:, fields: fields.merge(extra), mocks: network(**network_options), state:, previous:)
  end

  def payload(...) = board(...).data['data']

  def weather_marks(data) = (data['weather'] || []).select { it['type'] == 'weather' }

  def snapshot(milestones, sun: true)
    day = { hi: 18, lo: 13, condition: 'rain', rain_chance: 96, milestones:,
            sunrise_min: (7 * 60) + 5, sunset_min: (19 * 60) + 45 }
    { weather: { hi: 18, lo: 13, condition: 'rain', icon: 'wi-day-rain.svg', rain_chance: 96, unit: 'C', milestones:,
                 **(sun ? { perDay: [day] } : {}) },
      weatherFetchedAt: now_s - 600 }
  end

  # A sun at ten at night: "rain stops" is drawn as a sun, and after sunset that is a sun in the dark.
  it 'rain that stops after sunset is a clear night, not a sun' do
    marks = weather_marks(payload(state: snapshot([{ atMin: 16 * 60, kind: 'rain_starts' },
                                                   { atMin: 20 * 60, kind: 'rain_stops' }]), weather_fails: true))
    stops = marks.find { it['label'].to_s.match?(/20:00|8pm/) }
    starts = marks.find { it['label'].to_s.match?(/16:00|4pm/) }

    expect(stops).not_to be_nil, "no rain-stops marker came back: #{marks}"
    expect(stops['icon']).to match(/wi-night-clear/),
                             "rain stopping at 20:00, a quarter hour after sunset, drew #{stops['icon']}"
    expect(starts && starts['icon']).to match(/wi-rain/), "the start of the rain should be unchanged: #{starts}"
  end

  it 'rain that stops before sunrise is a clear night too' do
    marks = weather_marks(payload(state: snapshot([{ atMin: (6 * 60) + 30, kind: 'rain_stops' }]), weather_fails: true))

    expect(marks).not_to be_empty, 'no marker came back at all'
    expect(marks[0]['icon']).to match(/wi-night-clear/),
                                "rain stopping at 06:30, half an hour before sunrise, drew #{marks[0]['icon']}"
  end

  it 'a snapshot with no sun times keeps the sun it always drew' do
    marks = weather_marks(payload(state: snapshot([{ atMin: 20 * 60, kind: 'rain_stops' }], sun: false),
                                  weather_fails: true))

    expect(marks.first && marks.first['icon']).to match(/wi-day-sunny/),
                                                   "with no sun times it should draw what it always drew: #{marks}"
  end

  it 'rain that stops in daylight still clears to a sun' do
    marks = weather_marks(payload(state: snapshot([{ atMin: 11 * 60, kind: 'rain_stops' }]), weather_fails: true))

    expect(marks.first && marks.first['icon']).to match(/wi-day-sunny/),
                                                   "rain stopping at 11:00 should still be a sun: #{marks}"
  end

  it 'a replayed forecast old enough to be another day says so' do
    stale = { weather: { hi: 9, lo: 2, condition: 'snow', icon: 'wi-day-snow.svg', rain_chance: 70, unit: 'C',
                         milestones: [{ atMin: 600, kind: 'snow' }], sun: [{ kind: 'sunrise', atMin: 430 }] },
              weatherFetchedAt: now_s - (7 * 3600) }
    data = payload(state: stale, weather_fails: true)

    expect(data.dig('header_weather', 'hi')).to eq(9), "the old forecast was dropped rather than shown: #{data['header_weather']}"
    expect(data['weather_stale']).to be(true), 'a seven-hour-old forecast should be flagged stale'
  end

  it 'a feed that fails starts a clock, and clears it when it comes back' do
    down = board(calendars_fail: true)
    back = board(state: down.state)

    expect(down.state.dig('calendarDown', ics_url)).to eq(now_s), "the failure was not recorded: #{down.state['calendarDown']}"
    expect(back.state.dig('calendarDown', ics_url)).to be_falsy,
                                                       "a feed that answered again is still marked down: #{back.state['calendarDown']}"
  end

  it 'a feed that is not answering is named on THIS board, not on a later one' do
    first = payload(calendars_fail: true)
    known = board(state: { calendarDown: { ics_url => now_s - (10 * 60) }, calendarNames: { ics_url => 'Alex Personal' } },
                  calendars_fail: true)

    expect(first['calendars_down'].length).to eq(1),
                                              "a feed that failed on this very render was not named: #{first['calendars_down']}"
    expect(known.data.dig('data', 'calendars_down')).to eq(['Alex Personal']),
                                                        'expected the failing feed named on the board'
    expect(known.state.dig('calendarDown', ics_url)).to eq(now_s - (10 * 60)), 'the down-since clock was not carried'
  end

  it 'a feed that answers says nothing, so the mark means something' do
    expect(payload['calendars_down']).to eq([]), 'a board whose feeds all answered raised an alert'
  end

  it 'a failing feed keeps the name it had, instead of becoming its URL' do
    good = board
    later = payload(state: good.state.except('feeds'), calendars_fail: true)
    cold = payload(state: {}, calendars_fail: true)

    expect(good.state.dig('calendarNames', ics_url)).to eq('Alex Personal'),
                                                        "the feed name was not remembered: #{good.state['calendarNames']}"
    expect(later['calendars_down']).to eq(['Alex Personal']), 'the failing feed lost its name'
    expect(cold['calendars_down']).to contain_exactly(/Cal/),
                                      "expected a URL-derived name as the last resort, got #{cold['calendars_down']}"
  end

  # ------------------------------------------- the last good read of a feed

  def event_titles(data) = TransformA.titles(TransformA.event_items(data)).sort

  def drawn_events(data) = (data['events'] || []).select { it['type'] == 'event' }

  it 'every event says which calendar drew it, and state remembers when it answered' do
    good = board
    events = drawn_events(good.data['data'])

    expect(events).not_to be_empty, 'the healthy board drew no events'
    expect(events.map { it['f'] }).to all(eq(0)), 'an event does not say which calendar drew it'
    expect(good.state.dig('feedOk', ics_url)).to eq(now_s), "state did not record when the feed answered: #{good.state['feedOk']}"
    expect(JSON.generate(good.state).length).to be < 1500, 'saved state is carrying more than the clocks'
  end

  it 'a feed that fails is replayed from the last render, and says nothing yet' do
    good = board
    had = event_titles(good.data['data'])
    data = payload(state: good.state, previous: good.data['data'], calendars_fail: true)

    expect(had).not_to be_empty, 'the healthy board had no events to compare against'
    expect(event_titles(data)).to eq(had), 'the events were not replayed from the previous render'
    expect(data['calendars_down']).to eq([]), 'the board cried wolf about a feed whose day it was still showing'
    expect(drawn_events(data).map { it['f'] }).to all(eq(0)), 'the replayed events lost the mark saying which calendar drew them'
  end

  def gone_for(seconds, extra: {})
    good = board
    state = good.state.merge('feedOk' => good.state['feedOk'].merge(ics_url => now_s - seconds))
    [event_titles(good.data['data']), payload(state:, previous: good.data['data'], extra:, calendars_fail: true)]
  end

  it '...and once that feed has been silent six hours the board says so, still showing it' do
    had, data = gone_for((6 * 3600) + 60)

    expect(event_titles(data)).to eq(had), 'a stale day is still the best there is and must stay on the board'
    expect(data['calendars_down']).to eq(['Alex Personal']), 'a feed silent for six hours was not announced'
  end

  it 'a calendar silent for a whole day takes the band along the bottom' do
    had, data = gone_for((24 * 3600) + 60)
    band = data['service_alert']

    expect(band && band['kind']).to eq('feed'), "a day-old calendar did not reach the band: #{band}"
    expect(band['text']).to include('Alex Personal'), "the band does not say which calendar: #{band['text']}"
    expect(band['icon']).to be_nil, 'the feed band is asking for an icon off the network'
    expect(data['calendars_down']).to eq(['Alex Personal']), 'the quieter line was dropped'
    expect(event_titles(data)).to eq(had), 'the band replaced the day instead of announcing it'
  end

  it 'a calendar gone a day outranks the weather for the band' do
    _, data = gone_for((24 * 3600) + 60, extra: { alert_enabled: 'true', alert_rain_threshold: '10' })

    expect((data['service_alert'] || {})['kind']).to eq('feed'),
                                                     'the weather took the band from a calendar that has been gone a day'
  end

  it '...and under a day the weather keeps the band' do
    _, data = gone_for(7 * 3600, extra: { alert_enabled: 'true', alert_rain_threshold: '10' })

    expect((data['service_alert'] || {})['kind']).not_to eq('feed'), 'a feed down seven hours shouted over the weather'
    expect(data['calendars_down']).to eq(['Alex Personal']), 'it should still be named under the map'
  end

  it 'a previous render from another day is wrong, not stale, and is not used' do
    good = board
    data = payload(state: good.state, previous: good.data['data'].merge('date_iso' => '2019-01-01'), calendars_fail: true)

    expect(TransformA.event_items(data)).to eq([]), "yesterday's events were drawn as today's"
    expect(data['calendars_down']).to eq(['Alex Personal']), 'the feed took its day off the board and did not say so'
  end

  it 'with nothing to replay from, the feed is named at once' do
    data = payload(calendars_fail: true)

    expect(TransformA.event_items(data)).to eq([]), 'events appeared from nowhere'
    expect(data['calendars_down'].length).to eq(1), "a feed with nothing behind it was not named: #{data['calendars_down']}"
  end

  it 'only the feed that failed is replayed, so a healthy one is not doubled' do
    a_url = 'https://example.com/a.ics'
    b_url = 'https://example.com/b.ics'
    both = lambda do |fail_b|
      { Metro::FORECAST => { status: 503 }, Metro::I18N => { status: 404 },
        a_url => Metro.ics([{ start: '20260909T100000Z', end: '20260909T110000Z', summary: 'Alpha thing' }]),
        '*' => fail_b ? { status: 500 } : Metro.ics([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Beta thing' }]) }
    end
    two = TransformA.fields(config_json: JSON.generate(calendars: [{ url: a_url, name: 'Alpha' }, { url: b_url, name: 'Beta' }]))
    good = run_transform(now:, fields: two, mocks: both.call(false))
    data = run_transform(now:, fields: two, mocks: both.call(true), state: good.state, previous: good.data['data']).data['data']

    expect(event_titles(good.data['data'])).to eq(['Alpha thing', 'Beta thing']), 'the healthy board is not what this test assumes'
    expect(event_titles(data)).to eq(['Alpha thing', 'Beta thing']),
                                  'the failed feed was not replayed, or the healthy one was drawn twice'
    expect(data['calendars_down']).to eq([]), 'nothing was missing, so nothing should be announced'
  end

  it 'a previous render that is rubbish is dropped, not handed to the board' do
    junk = { date_iso: '2026-09-09', legend: [{ key: 'p0', name: 'Alex' }, 'not a line'],
             events: [{ type: 'event', f: 0, title: 'Kept', owner: 'p0', start_min: 600, end_min: 660 },
                      { type: 'event', f: 0, owner: 'p0', start_min: 700 },
                      { type: 'event', f: 0, title: 'No owner', owner: 'nope', start_min: 800 },
                      { type: 'event', f: 0, title: 'No clock', owner: 'p0' },
                      'not an object', nil] }
    data = payload(state: {}, previous: junk, calendars_fail: true)

    expect(data['board_notice']).to be_falsy, "a malformed previous render took this one down: #{data['board_notice']}"
    expect(TransformA.titles(TransformA.event_items(data))).to eq(['Kept']), 'the bad entries were not dropped one by one'
  end

  it "saved state stays under TRMNL's limit, for a household of twelve calendars" do
    events = (0...70).flat_map do |index|
      ['BEGIN:VEVENT', "UID:x#{index}@x", format('DTSTART:20260909T%02d0000Z', 7 + (index % 12)),
       format('DTEND:20260909T%02d0000Z', 8 + (index % 12)), "SUMMARY:A meeting title of the length people actually use #{index}",
       'LOCATION:Microsoft Teams Meeting, Room 214, Building B, Second Floor', 'END:VEVENT']
    end
    big = (['BEGIN:VCALENDAR', 'VERSION:2.0', 'X-WR-CALNAME:A calendar with quite a long name'] + events +
           ['END:VCALENDAR']).join("\r\n") << "\r\n"
    urls = (0...12).map { "https://a-fairly-long-host-name.example.com/calendars/user#{it}.ics" }
    mocks = { Metro::FORECAST => { status: 503 }, Metro::I18N => { status: 404 } }.merge(urls.to_h { [it, big] })
    run = run_transform(now:, fields: TransformA.fields(config_json: JSON.generate(calendars: urls.map { { url: it } })), mocks:)

    # trmnlp keeps the last good state when a write is over the limit, so `state` alone cannot show a rejected one.
    expect(run.log.grep(/Ignored trmnl_state/)).to be_empty, "TRMNL's limit is 8192 and over it the write is ignored"
    expect(run.state).not_to be_empty, 'no saved state came back'
    expect(JSON.generate(run.state).length).to be <= 8192, 'saved state came over 8192 bytes on twelve busy calendars'
  end

  it 'several feeds down are named in the order the config names them' do
    a_url = 'https://example.com/a.ics'
    b_url = 'https://example.com/b.ics'
    slow = { Metro::FORECAST => { status: 503 }, Metro::I18N => { status: 404 },
             a_url => { status: 500, body: '', delay: 0.3 }, b_url => { status: 500, body: '' } }
    fields = TransformA.fields(config_json: JSON.generate(calendars: [{ url: a_url, name: 'Alpha' }, { url: b_url, name: 'Beta' }]))

    expect(run_transform(now:, fields:, mocks: slow).data.dig('data', 'calendars_down')).to eq(%w[Alpha Beta]),
                                                                                         'the warning is ordered by whichever feed gave up first'
  end

  it 'state left over from feeds the config no longer names is dropped' do
    gone = 'https://gone.example.com/old.ics'
    run = board(state: { calendarDown: { gone => now_s - (3 * 3600) }, calendarNames: { gone => 'Old' } })

    expect(run.state['calendarDown']).to be_empty, "stale feed state survived: #{run.state}"
    expect(run.state['calendarNames'].keys).not_to include(gone), "stale feed state survived: #{run.state}"
    expect(run.data.dig('data', 'calendars_down')).to be_empty, 'a feed the config no longer has was announced as down'
  end

  it 'absent, string-wrapped and malformed state all render a board' do
    string_wrapped = JSON.generate(weather: { hi: 18, lo: 9, condition: 'clear', icon: 'wi-day-sunny.svg', unit: 'C' },
                                   weatherFetchedAt: now_s)
    [nil, nil, 'not json at all', string_wrapped, [1, 2, 3],
     { calendarDown: 'nope', calendarNames: [1], weather: 'sunny', i18n: { lang: 5 } }].each do |state|
      run = board(state:)

      expect(TransformA.event_items(run.data['data'])).not_to be_empty, "state #{state.inspect} broke the render"
      # `state` is what was kept, so a run that returned none would still show a Hash: feedOk proves this run wrote it.
      expect(run.state).to be_a(Hash).and(include('feedOk')), "state #{state.inspect} produced no new state"
    end
    expect(payload(state: string_wrapped).dig('header_weather', 'hi')).to eq(21).or(eq(18)),
                                                                         'a string-wrapped state was ignored'
  end

  it 'a render that falls back to the demo still returns its state' do
    run = board(state: { calendarNames: { ics_url => 'Alex Personal' } }, extra: { config_json: '' }, calendars_fail: true)

    # The seed has no feedOk, so only a state this run returned carries one.
    expect(run.state).to be_a(Hash).and(include('feedOk')), 'the fallback path dropped the state'
  end
end
