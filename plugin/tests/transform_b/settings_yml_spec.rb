# frozen_string_literal: true

require 'yaml'
require_relative '../support/transform_b'

# Ported from test/trmnl/transform/settings-yml.spec.js. His suite read the file with a 30-line regex reader
# because it had no YAML parser; this one has Ruby's, and reads every value as the text his reader saw.
RSpec.describe 'settings-yml' do
  settings_path = File.join(TransformB::REPO, 'plugin', 'src', 'settings.yml')
  source = File.read(File.join(TransformB::REPO, 'plugin', 'src', 'transform.js'))
  fields = YAML.safe_load_file(settings_path)['custom_fields'].map do |field|
    field.transform_values { it.is_a?(Array) ? it : it.to_s }
         .merge('options' => (field['options'] || []).map { it.is_a?(Hash) ? it.values.first.to_s : it.to_s },
                'conditions' => (field['conditional_validation'] || []).map { { 'when' => it['when'].to_s, 'hidden' => it['hidden'] || [] } })
  end
  by_key = fields.to_h { [it['keyname'], it] }

  it 'the form and the code agree on which settings exist' do
    read = source.scan(/\(\s*input\s*,\s*'([a-z0-9_]+)'/).flatten.uniq
    display_only = ['author_info']

    expect([fields.size > 5, read.size > 5, read.reject { by_key[it] }, by_key.keys - display_only - read])
      .to eq([true, true, [], []]), 'transform.js reads settings the form never offers, or the form offers settings nothing reads'
  end

  it 'every conditional names a field that exists, and a value that exists' do
    problems = fields.flat_map do |field|
      field['conditions'].flat_map do |condition|
        hidden = condition['hidden'].flat_map do |key|
          [("#{field['keyname']} hides \"#{key}\", which is not a setting" unless by_key[key]),
           ("#{field['keyname']} hides itself" if key == field['keyname'])]
        end
        allowed = { 'select' => field['options'], 'boolean' => %w[true false] }[field['field_type']]
        hidden + [("#{field['keyname']} has a rule for \"#{condition['when']}\"" if allowed && !allowed.include?(condition['when']))]
      end
    end

    expect(problems.compact).to eq([])
  end

  it 'a setting the board no longer reads is not still asked for' do
    %w[show_day switch_hour rolling_view].each do |key|
      expect([by_key.key?(key), source.include?("cf(input, '#{key}')")]).to eq([false, false]),
                                                                             "#{key} is still on the form or still read"
    end
  end

  it 'turning the alert banner off takes its thresholds with it' do
    off = by_key['alert_enabled']['conditions'].find { it['when'] == 'false' }&.fetch('hidden') || []

    expect(off).to include('alert_rain_threshold', 'alert_temp_low', 'alert_temp_high')
  end

  it 'nobody has to find a switch to see the board work' do
    demo = by_key['use_demo_data']
    hidden = demo['conditions'].flat_map { it['hidden'] }
    keys = by_key.keys

    expect([demo['default'], by_key['demo_set']['group'], hidden & %w[config_json demo_set],
            keys.index('use_demo_data') > keys.index('config_json')])
      .to eq(['false', demo['group'], [], true])
  end

  it 'every setting is optional and says what it does' do
    asked = fields.reject { it['field_type'] == 'author_bio' }

    expect(asked.reject { it['optional'] == 'true' && it['description'].to_s.length > 20 && !it['name'].to_s.empty? }
                .map { it['keyname'] }).to eq([]), 'not optional, no real description, or no label'
  end

  it 'a default is one of the choices offered' do
    offered = fields.select { it['field_type'] == 'select' && it.key?('default') }

    expect(offered.reject { it['options'].include?(it['default']) }.map { it['keyname'] }).to eq([])
  end

  it 'a description with a colon in it is quoted, or the file will not parse' do
    bad = File.readlines(settings_path, chomp: true).each_with_index.filter_map do |line, index|
      match = /^(\s+)(description|name|placeholder|help_text): (.*)$/.match(line)
      "line #{index + 1}: #{match[2]}" if match && !match[3].match?(/^['"|>]/) && match[3].include?(': ')
    end

    expect(bad).to eq([]), 'unquoted YAML scalars containing ": " -- trmnlp will refuse the file'
  end

  it 'no em dash reaches the reader' do
    bad = File.readlines(settings_path, chomp: true).each_with_index
              .filter_map { |line, index| "#{index + 1}: #{line.strip[0, 60]}" if line.include?("—") }

    expect(bad).to eq([]), 'em dash in settings.yml'
  end
end
