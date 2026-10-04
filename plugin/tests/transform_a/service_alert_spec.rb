# frozen_string_literal: true

require_relative '../support/transform_a'

# Ported from test/trmnl/transform/service-alert.spec.js. Wrapped in a module so its constants stay its own.
module ServiceAlertSpec
  RSpec.describe 'service-alert' do
    include TransformA::Helpers

    NOW = '2026-09-09T09:00:00Z'
    NOW_S = Time.utc(2026, 9, 9, 9).to_i
    ICS = Metro.ics([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' }])
    # Hours across the visible day. The wettest one is 17:00, the hour in the copy the alert lines were written against.
    HOURS = (7..21).map { format('2026-09-09T%02d:00', it) }
    PROBS = (7..21).map { { 17 => 80, 16 => 30 }.fetch(it, 5) }
    ON = { alert_enabled: 'true', alert_rain_threshold: '70' }.freeze
    NB = " "

    def alert(...) = TransformA.alert(...)
    def without(alert) = TransformA.without_parts(alert)

    # A forecast in the shape Open-Meteo answers with. `codes` is the hourly weathercode, left out by default:
    # that is the shape an older build saved, and the banner has to keep reading it.
    def forecast(hi: 18, lo: 11, max: 80, code: 61, probs: PROBS, codes: nil)
      { daily: { temperature_2m_max: [hi], temperature_2m_min: [lo], precipitation_probability_max: [max],
                 weathercode: [code], sunrise: ['2026-09-09T06:30'], sunset: ['2026-09-09T20:30'] },
        hourly: { time: HOURS, precipitation_probability: probs }.merge(codes ? { weathercode: codes } : {}) }
    end

    def net(body, i18n_text = nil, calendar: ICS)
      { Metro::FORECAST => body.nil? ? { status: 500 } : { json: body },
        Metro::I18N => i18n_text.nil? ? { status: 404 } : { body: i18n_text },
        '*' => calendar }
    end

    def board_fields(fields = {})
      TransformA.fields(lat_lon: '51.05,3.72',
                        config_json: JSON.generate(calendars: [{ url: 'https://example.com/a.ics', name: 'Cal' }]))
                .merge(fields)
    end

    def board(fields = {}, body: forecast, at: NOW, locale: 'en', state: nil, i18n: nil)
      run_transform(now: at, fields: board_fields(fields), mocks: net(body, i18n), locale:, state:)
    end

    def service_alert(...) = board(...).data.dig('data', 'service_alert')

    # ----------------------------------------------------------- the twilight

    it 'how long dusk lasts is computed for the place and the day, not assumed' do
      day = (board(ON).data.dig('data', 'days') || [])[0]

      expect(day && day['weather']).to be_truthy, 'no weather on the first day'
      expect(day['weather']['twilight_min']).to be_a(Numeric).and(be > 0)
      expect(day['weather']['twilight_min']).to be_between(25, 45).exclusive,
                                                "dusk at 51 degrees north in September came out as #{day['weather']['twilight_min']} minutes"
    end

    it '...and it follows the latitude, which is the whole point of computing it' do
      dusk_at = ->(lat_lon) { board(ON.merge(lat_lon:)).data.dig('data', 'days', 0, 'weather', 'twilight_min') }
      equator = dusk_at.call('-0.2,-78.5')
      far = dusk_at.call('60.15,-1.15')

      expect(equator).to be < far - 5,
                         "dusk on the equator (#{equator}) is not shorter than dusk at sixty north (#{far}), " \
                         'so the latitude is not reaching the sum'
    end

    it 'no alert settings, no banner: service_alert is null' do
      payload = board.data['data']

      expect(payload).to have_key('service_alert'), 'the payload has no service_alert key at all'
      expect(payload['service_alert']).to be_nil, 'an unconfigured board raised an alert'
    end

    it 'the banner is off until it is turned on, on a day that breaches everything' do
      expect(service_alert({ alert_rain_threshold: '10', alert_temp_low: '0' }, body: forecast(code: 71, hi: -2, lo: -9)))
        .to be_nil, 'a board with alert_enabled unset raised an alert'
    end

    it 'rain over the threshold is the banner: when it starts, when it ends, and how likely' do
      expect(without(service_alert(ON))).to eq(alert('rain', 'Rain from 17:00 until 18:00 (80%)', 'wi-rain.svg')),
                                            'the English rain banner'
    end

    # ---------------------------------------------------- the banner, in pieces

    it 'the banner comes in pieces: the thing bold, the clock quiet' do
      parts = service_alert(ON)['parts']
      styled = ->(style) { parts.select { it['s'] == style }.map { it['t'] } }

      expect(parts).to be_an(Array).and(be_any), "no parts: #{parts}"
      expect(parts.map { it['t'] }.join).to eq('Rain from 17:00 until 18:00 (80%)'), 'the pieces do not spell the line'
      expect(styled.call('b')).to eq(['Rain']), 'the thing itself is not the bold one'
      expect(styled.call('').join(' ')).to include('17:00').and(include('18:00')), "the clocks went quiet: #{parts}"
      expect(styled.call('q').join(' ')).to include('from').and(include('until')), 'the joining words are not quiet'
      expect(styled.call('q').join(' ')).to include('(80%)'), 'the probability is not quiet, or lost its brackets'
    end

    it 'a temperature keeps its degree and its unit in one piece' do
      parts = service_alert({ alert_temp_low: '-5' }.merge(ON), body: forecast(hi: 1, lo: -6))['parts']

      expect(parts.select { it['s'] == 'b' }.map { it['t'] }).to eq(['Freezing', "-6°C"]),
                                                                 "wanted the thing and its degree, each in one piece: #{parts}"
    end

    # ------------------------------------------ the until, when it is not a clock

    it 'a spell that ends in words lights the words, the way it lights a clock' do
      alert = service_alert(ON, body: forecast(probs: PROBS.each_index.map { it >= 10 ? 90 : 5 }))

      expect(alert['text']).to eq('Rain from 17:00 into the night (90%)'), 'the sentence'
      expect(alert['parts'].select { it['s'] == '' }.map { it['t'] }).to eq(['17:00', 'into the night']),
                                                                        "the until is not lit with the clock: #{alert['parts']}"
    end

    it '...and so does one that has already started and runs to the end' do
      alert = service_alert(ON, body: forecast(probs: PROBS.map { 90 }), at: '2026-09-09T15:30:00Z')

      expect(alert['text']).to eq('Rain for the rest of the day (90%)'), 'the sentence'
      expect(alert['parts'].select { it['s'] == '' }.map { it['t'] }).to eq(['for the rest of the day']),
                                                                        "the until is not lit: #{alert['parts']}"
    end

    it 'a day that stays under the threshold gets no banner' do
      expect(service_alert({ alert_enabled: 'true', alert_rain_threshold: '90' })).to be_nil
    end

    it 'a blank rain threshold is off, not zero' do
      pending 'TRMNL fills a blank field with its settings.yml default before the transform (core: custom_fields_values_with_defaults), so a blank threshold arrives as 70'
      expect(service_alert({ alert_enabled: 'true', alert_rain_threshold: '' })).to be_nil,
                                                                                     'an emptied rain field alerted on an 80% hour'
    end

    it 'snow outranks rain: one banner, and it names the thing that stops the day' do
      expect(without(service_alert(ON, body: forecast(code: 71, hi: 1, lo: -3))))
        .to eq(alert('snow', 'Snow from 17:00 until 18:00 (80%)', 'wi-snow.svg')),
            'a snowy day with rain over the threshold should read as snow'
    end

    it 'snow needs no setting: it alerts with the rain field emptied' do
      alert = service_alert({ alert_enabled: 'true', alert_rain_threshold: '' }, body: forecast(code: 71, hi: 4, lo: 1))

      expect((alert || {})['kind']).to eq('snow'), "got #{alert}"
    end

    # ---------------------------------------------------------------- combined

    def codes_at(by, otherwise: 3) = (7..21).map { by.fetch(it, otherwise) }

    it 'a day that breaches everything raises the one that takes the road away' do
      alert = service_alert({ alert_temp_low: '0' }.merge(ON),
                            body: forecast(code: 67, hi: 1, lo: -6, codes: codes_at({ 17 => 67 })))

      expect(without(alert)).to eq(alert('ice', 'Freezing rain from 17:00 until 18:00 (80%)', 'wi-sleet.svg')),
                                'a freezing, icy, wet day should name the ice'
    end

    it 'freezing rain is not rain: it alerts with the rain field emptied' do
      alert = service_alert({ alert_enabled: 'true', alert_rain_threshold: '' },
                            body: forecast(code: 66, hi: 2, lo: -1, codes: codes_at({ 17 => 66 })))

      expect((alert || {})['kind']).to eq('ice'), "got #{alert}"
    end

    it 'freezing drizzle is ice too, and outranks the snow behind it' do
      alert = service_alert(ON, body: forecast(code: 57, hi: 0, lo: -4, codes: codes_at({ 17 => 57 }, otherwise: 71)))

      expect(alert['kind']).to eq('ice'), 'freezing drizzle should be ice'
    end

    it 'snow outranks a freezing day: the sky before the thermometer' do
      alert = service_alert({ alert_temp_low: '0' }.merge(ON), body: forecast(code: 71, hi: -2, lo: -9))

      expect((alert || {})['kind']).to eq('snow'), "a freezing snowy day should say snow: #{alert}"
    end

    it 'snow outranks thunderstorms' do
      probs = (7..21).zip(PROBS).map { |hour, prob| [17, 18].include?(hour) ? 80 : prob }
      alert = service_alert(ON, body: forecast(code: 71, codes: codes_at({ 17 => 71, 18 => 95 }), probs:))

      expect(alert['kind']).to eq('snow'), 'snow and storms in one day should read as snow'
    end

    it 'hail arrives as thunderstorms, which is what it comes with' do
      [96, 99].each do |code|
        expect(service_alert(ON, body: forecast(code:, codes: codes_at({ 17 => code })))['kind']).to eq('storms'),
                                                                                                      "code #{code}"
      end
    end

    it 'cold and heat carry the temperature, and outrank rain' do
      cold = service_alert({ alert_temp_low: '-5' }.merge(ON), body: forecast(hi: 1, lo: -6))
      heat = service_alert({ alert_temp_high: '35' }.merge(ON), body: forecast(hi: 36, lo: 24))

      expect(without(cold)).to eq(alert('cold', 'Freezing, down to -6°C', 'wi-snowflake-cold.svg')), 'the cold banner'
      expect(without(heat)).to eq(alert('heat', 'Hot, up to 36°C', 'wi-hot.svg')), 'the heat banner'
    end

    it 'cold above freezing is called cold, not freezing' do
      alert = service_alert({ alert_temp_low: '5' }.merge(ON), body: forecast(hi: 9, lo: 3))

      expect(without(alert)).to eq(alert('cold', 'Cold, down to 3°C', 'wi-snowflake-cold.svg')), "got #{alert}"
    end

    # Blank cold and heat fields are a frost and a hot day in the board's own unit: each is the line itself
    # (fires) and one degree short of it (does not).
    [{ unit: 'c', at: { lo: 0 }, short: { lo: 1 }, kind: 'cold', text: 'Freezing, down to 0°C' },
     { unit: 'f', at: { lo: 32 }, short: { lo: 33 }, kind: 'cold', text: 'Freezing, down to 32°F' },
     { unit: 'c', at: { hi: 30 }, short: { hi: 29 }, kind: 'heat', text: 'Hot, up to 30°C' },
     { unit: 'f', at: { hi: 86 }, short: { hi: 85 }, kind: 'heat', text: 'Hot, up to 86°F' }].each do |default|
      it "a blank #{default[:kind]} field alerts at the default for #{default[:unit].upcase}" do
        mild = default[:unit] == 'f' ? { hi: 70, lo: 55 } : { hi: 21, lo: 13 }
        dry = { probs: PROBS.map { 5 }, max: 5 }
        fields = { alert_enabled: 'true', temperature_unit: default[:unit], alert_temp_low: '', alert_temp_high: '' }
        hit = service_alert(fields, body: forecast(**dry.merge(mild, default[:at])))
        miss = service_alert(fields, body: forecast(**dry.merge(mild, default[:short])))

        expect((hit || {})['text']).to eq(default[:text]), "got #{hit}"
        expect((hit || {})['kind']).to eq(default[:kind]), 'the kind'
        expect(miss).to be_nil, "a degree short of the default alerted: #{miss}"
      end
    end

    it 'a filled-in temperature field overrides the default' do
      alert = service_alert({ alert_enabled: 'true', alert_temp_low: '-5' }, body: forecast(hi: 8, lo: -2, probs: PROBS.map { 5 }))

      expect(alert).to be_nil, "got #{alert}"
    end

    it 'a temperature threshold is read in the unit the board is showing' do
      pending 'TRMNL fills the emptied alert_rain_threshold with its default (70) before the transform, so the 80% hour alerts'
      same_day = { %r{\Ahttps://api\.open-meteo\.com/.*temperature_unit=fahrenheit} => { json: forecast(hi: 81, lo: 64) },
                   Metro::FORECAST => { json: forecast(hi: 27, lo: 18) },
                   '*' => ICS }
      no_rain = ON.merge(alert_rain_threshold: '', alert_temp_low: '20')
      on_scale = lambda do |unit|
        run_transform(now: NOW, fields: board_fields({ temperature_unit: unit }.merge(no_rain)), mocks: same_day)
          .data.dig('data', 'service_alert')
      end

      expect(without(on_scale.call('c'))).to eq(alert('cold', 'Cold, down to 18°C', 'wi-snowflake-cold.svg')),
                                             '18C is at or below a threshold of 20 on a Celsius board'
      expect(on_scale.call('f')).to be_nil, '64F is nowhere near a threshold of 20 on a Fahrenheit board'
    end

    it 'a snapshot saved in one unit is compared in the unit the board now shows' do
      good = board({ temperature_unit: 'c' }.merge(ON), body: forecast(hi: 1, lo: -6))
      later = service_alert({ temperature_unit: 'f', alert_temp_low: '25', alert_rain_threshold: '' }.merge(ON),
                            body: nil, state: good.state)

      expect(good.state.dig('weather', 'unit')).to eq('C'), 'the snapshot should record the unit it was fetched in'
      expect(without(later)).to eq(alert('cold', 'Freezing, down to 21°F', 'wi-snowflake-cold.svg')), "got #{later}"
    end

    it 'the alert costs the render no extra network call' do
      run = board(ON)
      forecast_calls = run.requests.map { it[:url] }.grep(/api\.open-meteo\.com/)

      expect(run.data.dig('data', 'service_alert')).to be_truthy, 'no alert to weigh'
      expect(forecast_calls.length).to eq(1), 'the forecast API was called more than once'
    end

    it 'a board running on the last good forecast still raises its alert' do
      saved = board(ON).state
      later = service_alert(ON, body: nil, state: saved)

      expect(saved.dig('weather', 'peak')).to be_truthy, "the wettest hour was not saved: #{saved['weather']}"
      expect((later || {})['text']).to eq('Rain from 17:00 until 18:00 (80%)'), "got #{later}"
    end

    it 'a saved snapshot from a build that had no wettest hour does not invent one' do
      saved = { weather: { hi: 18, lo: 11, condition: 'rain', icon: 'wi-day-rain.svg', rain_chance: 80, unit: 'C' },
                weatherFetchedAt: NOW_S - 600 }
      alert = service_alert(ON, body: nil, state: saved)

      expect(alert).to be_nil, "got #{alert}"
    end

    # The exact copy, per language, from the files this repo ships, served through the fetch path. NB is the
    # no-break space French and German put before a percent sign.
    {
      'en' => { ahead: 'Rain from 17:00 until 18:00 (80%)', started: 'Rain until 16:00 (85%)',
                snow: 'Snow for the rest of the day (90%)', cold: 'Freezing, down to -3°C' },
      'de' => { ahead: "Regen von 17:00 bis 18:00 (80#{NB}%)", started: "Regen bis 16:00 (85#{NB}%)",
                snow: "Schnee für den Rest des Tages (90#{NB}%)", cold: 'Frost, Tiefstwert -3°C' },
      'es' => { ahead: 'Lluvia de 17:00 a 18:00 (80%)', started: 'Lluvia hasta las 16:00 (85%)',
                snow: 'Nieve el resto del día (90%)', cold: 'Heladas, mínima de -3°C' },
      'fr' => { ahead: "Pluie de 17:00 à 18:00 (80#{NB}%)", started: "Pluie jusqu'à 16:00 (85#{NB}%)",
                snow: "Neige jusqu'à la fin de la journée (90#{NB}%)", cold: 'Gel, minimum -3°C' },
      'nl' => { ahead: 'Regen van 17:00 tot 18:00 (80%)', started: 'Regen tot 16:00 (85%)',
                snow: 'Sneeuw de rest van de dag (90%)', cold: 'Vorst, minimum -3°C' }
    }.each do |lang, want|
      it "the #{lang} banner reads as it was written" do
        table = lang == 'en' ? nil : TransformA.i18n_file(lang)
        locale = lang == 'en' ? 'en-GB' : "#{lang}-#{lang.upcase}"
        got = ->(at, body) { service_alert(ON, body:, at:, locale:, i18n: table) || {} }

        expect(got.call(NOW, forecast)['text']).to eq(want[:ahead]), "#{lang}: a spell still ahead"
        # 15:30, inside the 15:00 hour
        expect(got.call('2026-09-09T15:30:00Z', forecast(probs: HOURS.each_index.map { it == 8 ? 85 : 5 }))['text'])
          .to eq(want[:started]), "#{lang}: a spell that has started"
        # 17:00 to the last hour, 21:00, read at 17:30
        snowing = forecast(code: 71, probs: HOURS.each_index.map { it >= 10 ? 90 : 5 }, codes: HOURS.map { 73 })
        expect(got.call('2026-09-09T17:30:00Z', snowing)['text']).to eq(want[:snow]), "#{lang}: snow to the end of the day"
        expect(got.call(NOW, forecast(hi: 4, lo: -3, probs: HOURS.map { 5 }))['text']).to eq(want[:cold]),
                                                                                       "#{lang}: the frost line"
      end
    end

    it 'an unreachable language file leaves an English banner, not a broken one' do
      alert = service_alert(ON, locale: 'fr-FR')

      expect(without(alert)).to eq(alert('rain', 'Rain from 17:00 until 18:00 (80%)', 'wi-rain.svg')), "got #{alert}"
    end

    it 'the banner follows the 12-hour setting like every other time on the board' do
      alert = service_alert({ time_format: '12h' }.merge(ON))

      expect((alert || {})['text']).to eq('Rain from 5pm until 6pm (80%)'), "got #{alert}"
    end

    it 'a board with no location cannot raise an alert' do
      alert = service_alert({ lat_lon: '' }.merge(ON))

      expect(alert).to be_nil, "got #{alert}"
    end

    it 'a demo board can show the banner without waiting for real weather' do
      fields = TransformA.fields(use_demo_data: 'true', demo_set: 'friends', alert_enabled: 'true', alert_temp_low: '0')
      alert = run_transform(now: NOW, fields:, mocks: { '*' => { status: 500 } }).data.dig('data', 'service_alert')

      expect(without(alert)).to eq(alert('snow', 'Snow from 15:00 until 17:00 (80%)', 'wi-snow.svg')),
                                "the freezing demo board should demonstrate the banner: #{alert}"
    end

    # -------------------------------------------------------------------
    # Nothing in the past.
    # -------------------------------------------------------------------

    D0 = '2026-09-09'
    D1 = '2026-09-10'
    BOTH_DAYS = Metro.ics([{ start: '20260909T140000Z', end: '20260909T150000Z', summary: 'Afternoon' },
                           { start: '20260910T140000Z', end: '20260910T150000Z', summary: 'Tomorrow afternoon' }])

    # The shape a DAY_SPAN board asks for: daily arrays with one entry per day of the run, one hourly array across
    # all of them. `codes` and `degs` are by hour; with no day carrying any, they are left out entirely.
    def forecast_days(days)
      hours = days.flat_map { |day| (7..21).map { day.merge(hour: it) } }
      hourly = { time: hours.map { format('%sT%02d:00', it[:date], it[:hour]) },
                 precipitation_probability: hours.map { (it[:by] || {}).fetch(it[:hour], 5) } }
      hourly[:weathercode] = hours.map { (it[:codes] || {}).fetch(it[:hour], 3) } if days.any? { it[:codes] }
      if days.any? { it[:degs] }
        hourly[:temperature_2m] = hours.map { |hour| (hour[:degs] || {}).fetch(hour[:hour]) { hour[:fill] || hour[:lo] || 11 } }
      end
      { daily: { temperature_2m_max: days.map { it[:hi] || 18 }, temperature_2m_min: days.map { it[:lo] || 11 },
                 precipitation_probability_max: days.map { it[:max] || 80 }, weathercode: days.map { it[:code] || 61 },
                 sunrise: days.map { "#{it[:date]}T06:30" }, sunset: days.map { "#{it[:date]}T20:30" } },
        hourly: }
    end

    def at(hour, minute = 0) = format('2026-09-09T%02d:%02d:00Z', hour, minute)

    def run_at(now, body, fields = ON, state: nil, i18n: nil, locale: 'en')
      run_transform(now:, fields: board_fields(fields), state:, locale:,
                    mocks: net(body, i18n, calendar: BOTH_DAYS))
    end

    def alert_at(now, body, fields = {}, lang = nil)
      run_at(now, body, ON.merge(fields || {}), i18n: lang && lang[:text], locale: lang ? lang[:code] : 'en')
        .data.dig('data', 'service_alert')
    end

    it 'the wettest hour of the day is not an alert once it has gone' do
      alert = alert_at(at(15), forecast_days([{ date: D0, by: { 9 => 90 } }]))

      expect(alert).to be_nil, "got #{alert}"
    end

    it 'when the wettest hour has gone, the banner names the wettest one still to come' do
      alert = alert_at(at(15), forecast_days([{ date: D0, by: { 9 => 90, 18 => 75 } }]))

      expect((alert || {})['text']).to eq('Rain from 18:00 until 19:00 (75%)'), "got #{alert}"
    end

    it 'the hour that is happening right now is still ahead enough to warn about' do
      body = forecast_days([{ date: D0, by: { 15 => 85 } }])

      expect((alert_at(at(15), body) || {})['text']).to eq('Rain until 16:00 (85%)')
      expect((alert_at(at(15, 59), body) || {})['text']).to eq('Rain until 16:00 (85%)')
      expect(alert_at(at(16), body)).to be_nil, 'an hour that ended still alerted'
    end

    it 'a certainty says nothing about its chance' do
      alert = alert_at(at(15), forecast_days([{ date: D0, by: { 15 => 100 } }]))
      nearly = alert_at(at(15), forecast_days([{ date: D0, by: { 15 => 99 } }]))

      expect((alert || {})['text']).to eq('Rain until 16:00'), "got #{alert}"
      expect((alert['parts'] || []).map { it['t'] }).not_to(include(/%/), "a piece still carries a per-cent: #{alert['parts']}")
      expect((nearly || {})['text']).to eq('Rain until 16:00 (99%)'), "got #{nearly}"
    end

    it 'every language drops its own bracket at a certainty' do
      Dir[File.join(TransformA::I18N_DIR, '*.json')].each do |file|
        code = File.basename(file, '.json')
        lang = { code:, text: File.read(file) }
        sure = alert_at(at(15), forecast_days([{ date: D0, by: { 15 => 100 } }]), nil, lang)
        maybe = alert_at(at(15), forecast_days([{ date: D0, by: { 15 => 90 } }]), nil, lang)
        words = JSON.parse(lang[:text])
        said = words['alert_until'].sub('{what}', words['alert_kind_rain']).sub('{u}', '16:00').sub('{p}', '90')

        expect([sure, maybe]).to all(be_truthy), "#{code}: no alert"
        expect(maybe['text']).to eq(said), "#{code}: the board did not read in its own language"
        expect(sure['text'].gsub(/\d+:\d+/, '')).not_to match(/[%\d]/), "#{code}: a chance survived: #{sure['text']}"
        expect(maybe['text']).to include('90'), "#{code}: the chance was dropped when it was not certain"
        expect(maybe['text']).to start_with(sure['text']),
                                 "#{code}: the sentence changed, not just its bracket: #{[sure['text'], maybe['text']]}"
      end
    end

    # -------------------------------------------------------------------
    # When it ENDS.
    # -------------------------------------------------------------------

    it 'a spell ahead is named from its first hour to the end of its last' do
      alert = alert_at(at(9), forecast_days([{ date: D0, by: { 14 => 75, 15 => 90, 16 => 72, 17 => 40 } }]))

      expect((alert || {})['text']).to eq('Rain from 14:00 until 17:00 (90%)'), "got #{alert}"
    end

    it 'once it has started the banner says only when it stops' do
      alert = alert_at(at(14, 20), forecast_days([{ date: D0, by: { 13 => 95, 14 => 80, 15 => 75 } }]))

      expect((alert || {})['text']).to eq('Rain until 16:00 (80%)'), "got #{alert}"
    end

    it 'a spell that runs past the last hour has no end to name' do
      body = forecast_days([{ date: D0, by: { 19 => 80, 20 => 85, 21 => 90 } }])

      expect((alert_at(at(9), body) || {})['text']).to eq('Rain from 19:00 into the night (90%)')
      expect((alert_at(at(19, 30), body) || {})['text']).to eq('Rain for the rest of the day (90%)')
    end

    it 'the NEXT spell is the banner, not the wettest one' do
      alert = alert_at(at(9), forecast_days([{ date: D0, by: { 10 => 72, 18 => 95 } }]))

      expect((alert || {})['text']).to eq('Rain from 10:00 until 11:00 (72%)'), "got #{alert}"
    end

    it 'a dry hour in the middle is two spells, and the banner names the first' do
      alert = alert_at(at(9), forecast_days([{ date: D0, by: { 12 => 80, 13 => 20, 14 => 80, 15 => 80 } }]))

      expect((alert || {})['text']).to eq('Rain from 12:00 until 13:00 (80%)'), "got #{alert}"
    end

    it 'the hourly codes name snow and thunderstorms, each with its own icon' do
      snow = alert_at(at(9), forecast_days([{ date: D0, by: { 11 => 60, 12 => 70 }, codes: { 11 => 71, 12 => 73 } }]))
      storms = alert_at(at(9), forecast_days([{ date: D0, by: { 16 => 55, 17 => 65 }, codes: { 16 => 95, 17 => 96 } }]))

      expect(without(snow)).to eq(alert('snow', 'Snow from 11:00 until 13:00 (70%)', 'wi-snow.svg')), "got #{snow}"
      expect(without(storms)).to eq(alert('storms', 'Thunderstorms from 16:00 until 18:00 (65%)', 'wi-thunderstorm.svg')),
                                 "got #{storms}"
    end

    it 'thunderstorms alert under the rain line, and outrank the rain before them' do
      alert = alert_at(at(9), forecast_days([{ date: D0, by: { 10 => 90, 19 => 55 }, codes: { 10 => 61, 19 => 95 } }]))
      unlikely = alert_at(at(9), forecast_days([{ date: D0, by: { 19 => 40 }, codes: { 19 => 95 } }]))

      expect((alert || {})['text']).to eq('Thunderstorms from 19:00 until 20:00 (55%)'), "got #{alert}"
      expect(unlikely).to be_nil, "a 40% thunderstorm alerted: #{unlikely}"
    end

    it 'a dry code on a wet hour is still the rain the reader drew the line on' do
      alert = alert_at(at(9), forecast_days([{ date: D0, by: { 12 => 85 }, codes: { 12 => 3 } }]))

      expect((alert || {})['text']).to eq('Rain from 12:00 until 13:00 (85%)'), "got #{alert}"
    end

    it 'hours saved without codes read as their day did' do
      fetched_at = Time.iso8601(at(8)).to_i
      saved = { weather: { hi: 1, lo: -3, condition: 'snow', unit: 'C', date: D0,
                           perDay: [{ hi: 1, lo: -3, condition: 'snow',
                                      hours: [{ atMin: 600, pct: 80 }, { atMin: 660, pct: 85 }, { atMin: 720, pct: 5 }] }] },
                weatherFetchedAt: fetched_at }
      stormy = { weather: { hi: 20, lo: 14, condition: 'storms', unit: 'C', date: D0,
                            perDay: [{ hi: 20, lo: 14, condition: 'storms', hours: [{ atMin: 600, pct: 80 }] }] },
                 weatherFetchedAt: fetched_at }
      snow = run_at(at(8), nil, state: saved).data.dig('data', 'service_alert')
      storm = run_at(at(8), nil, state: stormy).data.dig('data', 'service_alert')

      expect(without(snow)).to eq(alert('snow', 'Snow from 10:00 until 12:00 (85%)', 'wi-snow.svg')), "got #{snow}"
      expect((storm || {})['kind']).to eq('rain'), "an hour with no code was called a thunderstorm: #{storm}"
    end

    it 'the codes come in the same one request and are saved with the hours' do
      run = run_at(at(8), forecast_days([{ date: D0, by: { 12 => 85 }, codes: { 12 => 63 } }]))
      forecast_calls = run.requests.map { it[:url] }.grep(/api\.open-meteo\.com/)

      expect(forecast_calls.length).to eq(1), 'the forecast API calls'
      expect(forecast_calls[0]).to match(/hourly=precipitation_probability%2Cweathercode/),
                                   "hourly codes were not asked for: #{forecast_calls[0]}"
      expect(run.state.dig('weather', 'perDay', 0, 'hours', 5)).to eq('atMin' => 12 * 60, 'pct' => 85, 'code' => 63),
                                                                   'the saved hour'
    end

    it 'a snowy morning read in the evening raises nothing' do
      morning = alert_at(at(19), forecast_days([{ date: D0, code: 71, by: { 9 => 90 } }]))
      dry = alert_at(at(19), forecast_days([{ date: D0, code: 71, by: { 9 => 90, 20 => 30 } }]))
      late = alert_at(at(19), forecast_days([{ date: D0, code: 71, by: { 9 => 90, 20 => 80 } }]))

      expect(morning).to be_nil, "got #{morning}"
      expect(dry).to be_nil, "named a 30% hour as heavy snow: #{dry}"
      expect((late || {})['text']).to eq('Snow from 20:00 until 21:00 (80%)'), "snow still to come is still an alert: #{late}"
    end

    # ---------------------------------------------- cold and heat, by the hour

    HOT = { alert_temp_high: '35' }.freeze

    it 'heat is the stretch of the day that is hot, and says which stretch' do
      alert = alert_at(at(9), forecast_days([{ date: D0, hi: 36, lo: 24, fill: 24,
                                               degs: { 13 => 35, 14 => 36, 15 => 36, 16 => 35 } }]), HOT)

      expect(without(alert)).to eq(alert('heat', 'Hot, up to 36°C (13:00–17:00)', 'wi-hot.svg')), "got #{alert}"
    end

    it 'heat that is over is not an alert, however hot the day was' do
      alert = alert_at(at(20), forecast_days([{ date: D0, hi: 36, lo: 24, fill: 24,
                                                degs: { 13 => 35, 14 => 36, 15 => 36, 16 => 35 } }]), HOT)

      expect(alert).to be_nil, "warned at eight in the evening about an afternoon that was over: #{alert}"
    end

    it 'cold at dawn is an alert at dawn and not at lunchtime' do
      day = [{ date: D0, hi: 9, lo: -4, fill: 8, degs: { 7 => -4, 8 => -2 } }]
      early = alert_at(at(7), forecast_days(day))
      late = alert_at(at(12), forecast_days(day))

      expect(without(early)).to eq(alert('cold', 'Freezing, down to -4°C (07:00–09:00)', 'wi-snowflake-cold.svg')),
                                "got #{early}"
      expect(late).to be_nil, "still warning about frost at midday: #{late}"
    end

    it 'the stretch opens at the hour you are standing in, not before it' do
      alert = alert_at(at(13, 30), forecast_days([{ date: D0, hi: 38, lo: 24, fill: 24,
                                                    degs: { 11 => 36, 12 => 38, 13 => 37, 14 => 36, 15 => 35 } }]), HOT)

      expect(without(alert)).to eq(alert('heat', 'Hot, up to 37°C (13:00–16:00)', 'wi-hot.svg')), "got #{alert}"
    end

    it 'a single hot hour is still a stretch, with both its ends' do
      alert = alert_at(at(9), forecast_days([{ date: D0, hi: 36, lo: 24, fill: 24, degs: { 15 => 36 } }]), HOT)

      expect((alert || {})['text']).to eq('Hot, up to 36°C (15:00–16:00)'), "got #{alert}"
    end

    it 'a day whose hours carry no temperature is still read as a whole day' do
      alert = alert_at(at(20), forecast_days([{ date: D0, hi: 36, lo: 24, by: { 9 => 90 } }]), HOT)

      expect(without(alert)).to eq(alert('heat', 'Hot, up to 36°C', 'wi-hot.svg')), "got #{alert}"
    end

    it 'the stretch is lit and the sentence around it is not' do
      alert = alert_at(at(9), forecast_days([{ date: D0, hi: 36, lo: 24, fill: 24, degs: { 13 => 36, 14 => 36 } }]), HOT)
      styled = ->(style) { alert['parts'].select { it['s'] == style }.map { it['t'] } }

      expect(alert['parts'].map { it['t'] }.join).to eq(alert['text']), 'the pieces do not spell the line'
      expect(styled.call('b')).to eq(['Hot', "36°C"]), "the thing and its degree are not the bold ones: #{alert['parts']}"
      expect(styled.call('').join).to include('13:00').and(include('15:00')), "the clocks went quiet: #{alert['parts']}"
    end

    it 'the wettest hour of TOMORROW is not an alert about today' do
      alert = alert_at(at(9), forecast_days([{ date: D0, max: 20, by: {} }, { date: D1, max: 95, by: { 17 => 95 } }]))

      expect(alert).to be_nil, "got #{alert}"
    end

    it 'the banner is about the day the board is drawing' do
      alert = alert_at(at(9), forecast_days([{ date: D0, max: 88, by: { 9 => 88 } },
                                             { date: D1, max: 92, by: { 16 => 92 } }]))

      expect((alert || {})['text']).to eq('Rain until 10:00 (88%)'), "the banner should be about today: #{alert}"
    end

    it "a board replaying this morning's snapshot does not replay this morning's alert" do
      morning = run_at(at(8), forecast_days([{ date: D0, by: { 9 => 90 } }]))
      evening = run_at(at(19), nil, state: morning.state).data.dig('data', 'service_alert')

      expect(morning.data.dig('data', 'service_alert', 'text')).to eq('Rain from 09:00 until 10:00 (90%)'),
                                                                   'the morning board should warn about the morning'
      expect(evening).to be_nil, "the evening board replayed the morning: #{evening}"
    end

    it 'a snapshot with only a wettest hour behind it is still held to the clock' do
      saved = { weather: { hi: 18, lo: 11, condition: 'rain', icon: 'wi-day-rain.svg', rain_chance: 90, unit: 'C',
                           peak: { atMin: 9 * 60, pct: 90 } },
                weatherFetchedAt: Time.iso8601(at(8)).to_i }
      late = run_at(at(15), nil, state: saved).data.dig('data', 'service_alert')
      still = run_at(at(8), nil, state: saved).data.dig('data', 'service_alert')

      expect(late).to be_nil, "got #{late}"
      expect(without(still)).to eq(alert('rain', 'Rain around 09:00 (90%)', 'wi-rain.svg')),
                                "the same snapshot read before the hour is a real warning: #{still}"
    end

    it 'the demo board obeys the clock like a real one' do
      fields = TransformA.fields(use_demo_data: 'true', demo_set: 'simpsons', alert_enabled: 'true',
                                 alert_rain_threshold: '50')
      alert = run_transform(now: at(20), fields:, mocks: { '*' => { status: 500 } }).data.dig('data', 'service_alert')

      expect(alert).to be_nil, "the demo raised an alert about an hour that has gone: #{alert}"
    end

    it 'the hourly detail behind the alert is saved, per day' do
      run = run_at(at(8), forecast_days([{ date: D0, by: { 9 => 90, 18 => 75 } }, { date: D1, by: { 17 => 95 } }]))
      per_day = run.state.dig('weather', 'perDay')

      expect(per_day).to be_an(Array).and(have_attributes(length: 2)), "expected two days: #{per_day}"
      expect(per_day[0]['peak']).to eq('atMin' => 9 * 60, 'pct' => 90), 'day 0 wettest hour'
      expect(per_day[1]['peak']).to eq('atMin' => 17 * 60, 'pct' => 95), 'day 1 wettest hour'
      expect(per_day[0]['hours'].length).to eq(15), "day 0 should carry 07:00-21:00: #{per_day[0]['hours']}"
      expect(per_day[0]['hours'][11]).to eq('atMin' => 18 * 60, 'pct' => 75), "the hours are the day's own"
    end

    it 'a snapshot that outlived its own day is read as the day it describes' do
      body = forecast_days([{ date: D0, by: { 9 => 90 } }, { date: D1, by: { 16 => 85 } }])
      saved = run_at('2026-09-09T23:30:00Z', body).state
      alert = run_at('2026-09-10T04:00:00Z', nil, state: saved).data.dig('data', 'service_alert')

      expect(saved.dig('weather', 'date')).to eq(D0), 'the snapshot should record which day it starts on'
      expect((alert || {})['text']).to eq('Rain from 16:00 until 17:00 (85%)'),
                                       "the morning after should be warned about the morning after: #{alert}"
    end

    it 'a snapshot older than the run it covers says nothing rather than something wrong' do
      body = forecast_days([{ date: D0, by: { 9 => 90 } }, { date: D1, by: { 16 => 85 } }])
      saved = run_at(at(8), body).state
      alert = run_at('2026-09-11T08:00:00Z', nil, state: saved).data.dig('data', 'service_alert')

      expect(alert).to be_nil, "a forecast that ran out raised an alert anyway: #{alert}"
    end
  end
end
