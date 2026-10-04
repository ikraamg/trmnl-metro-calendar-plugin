# frozen_string_literal: true

require 'json'
require 'rbconfig'

# Ported from test/trmnl/lint.spec.js: trmnlp lint, as plugin/lint.sh runs it, clean apart from the stale lat_lon warning.
RSpec.describe 'lint' do
  it 'trmnlp lint is clean, apart from the stale lat_lon field type' do
    settings = File.read(File.join(TRMNLP::Testing.plugin_dir, 'src', 'settings.yml'))
    expect(settings).to match(/field_type: lat_lon/),
                        'settings.yml no longer uses lat_lon: delete the exception here and in plugin/lint.sh'

    output = IO.popen([RbConfig.ruby, $PROGRAM_NAME, 'lint', '--format', 'json'], chdir: TRMNLP::Testing.plugin_dir,
                                                                               err: %i[child out], &:read)
    lint = JSON.parse(output[/\{.*\}/m] || 'null') or raise "trmnlp lint failed:\n#{output}"
    left = lint['issues'].map { it['message'] }.reject { it.include?('unknown field_type: lat_lon') }

    expect(left).to be_empty, "trmnlp lint: #{left.size} issue(s):\n#{left.join("\n")}"
  end
end
