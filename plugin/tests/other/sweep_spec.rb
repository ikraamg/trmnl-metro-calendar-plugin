# frozen_string_literal: true

require_relative '../support/layout_extra'

# Ported from test/trmnl/sweep.spec.js: the three example days, through the real transform at five times of day,
# drawn on all six views. A fault fails, and so does a loss against test/trmnl/sweep.baseline.json;
# `trmnlp test --update` rewrites a board's baseline entry, as `trmnlp-test run sweep -u` did.
RSpec.describe 'sweep' do
  sets = %w[simpsons futurama friends]
  times = %w[07:30 12:00 16:30 21:30 23:40]
  views = {
    'x-landscape' => { device: 'v2', view: 'full' },
    'x-portrait' => { device: 'v2', view: 'full', orientation: :portrait },
    'og-landscape' => { device: 'og_png', view: 'full' },
    'og-half-horizontal' => { device: 'og_png', view: 'half_horizontal' },
    'og-half-vertical' => { device: 'og_png', view: 'half_vertical' },
    'og-quadrant' => { device: 'og_png', view: 'quadrant' }
  }
  baseline = File.join(MetroLayout::REPOSITORY, 'test', 'trmnl', 'sweep.baseline.json')
  # which way each loss is allowed to move, and what it means
  worse = { 'shed' => :>, 'dropped' => :>, 'caps' => :<, 'timed' => :< }
  means = { 'shed' => 'caption(s) not placed', 'dropped' => 'person/people off the board',
            'caps' => 'caption(s) drawn', 'timed' => 'caption(s) with their time' }

  # What a board loses: captions not placed, people left off, captions drawn, and captions that kept their clock.
  def losses(report)
    captions = report['labels'].select { MetroLayout.class?(it, 'metro-label') }
    { 'shed' => report['debug']['shed'] || 0, 'dropped' => (report['debug']['dropped'] || []).size,
      'caps' => captions.size, 'timed' => captions.count { !it['timeCls'].to_s.empty? } }
  end

  def bless(file, key, lost)
    all = File.exist?(file) ? JSON.parse(File.read(file)) : {}
    all[key] = lost
    File.write(file, "#{JSON.pretty_generate(all.sort.to_h)}\n")
  end

  sets.product(times, views.keys).each do |set, time, on|
    key = "#{set} #{time} #{on}"
    it "sweep · #{key}" do
      hour, minute = time.split(':').map(&:to_i)
      # America/Chicago in September is UTC-5
      inputs = { now: Time.utc(2026, 9, 15) + ((hour + 5) * 3600) + (minute * 60),
                 variables: MetroLayout.trmnl_variables(time_zone: 'America/Chicago', locale: 'en-US', instance_name: 'Metro'),
                 custom_fields: { use_demo_data: 'true', demo_set: set, time_format: '12h' }, data: {},
                 mocks: MetroLayout.demo_mocks.merge(MetroLayout::NOT_FOUND) }
      # trmnlp's render keeps no transform output, so the transform is asked on its own, with the same inputs
      run = trmnl.transform(device: views[on][:device], orientation: views[on].fetch(:orientation, :landscape), **inputs)
      expect(run.error).to be_nil
      expect(run).to stay_within_serverless_limits
      expect((run.data.dig('data', 'legend') || []).size).to be > 0, 'the example day came back empty'
      options = MetroLayout.render_options(views[on])
      report = MetroLayout.checked_report(trmnl.render(**options, **inputs))

      lost = losses(report)
      updating = ENV.key?(TRMNLP::Testing::Snapshot::UPDATE_ENV_KEY)
      bless(baseline, key, lost) if updating
      was = (JSON.parse(File.read(baseline))[key] if File.exist?(baseline))
      # a board the baseline has never seen is recorded (--update) and not judged
      slipped = worse.filter_map do |loss, direction|
        next if !was || updating || was[loss].nil? || !lost[loss].public_send(direction, was[loss])

        "#{loss} #{was[loss]} -> #{lost[loss]}  (#{means[loss]})"
      end
      faults = report['debug']['faults']
      puts "#{slipped.any? || faults.any? ? 'FAIL ' : 'ok   '}#{key.ljust(36)} runs #{report['debug']['runs']} " \
           "#{lost.to_json}#{" was #{was.to_json}" if was}#{" faults #{faults.to_json}" if faults.any?}"

      aggregate_failures do
        expect(faults).to eq([]), "#{key}: the board knows it is wrong: #{faults.to_json}"
        expect(slipped).to eq([]), "#{key} lost something. If it is meant, read it, then: trmnlp test --update\n" \
                                   "#{slipped.join("\n")}"
      end
    end
  end
end
