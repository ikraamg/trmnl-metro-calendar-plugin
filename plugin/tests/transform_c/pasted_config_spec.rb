# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/pasted-config.spec.js: the three cases that run the transform. The other nine
# call parseConfig inside transform.js, so they stay in the Node runner.
RSpec.describe 'pasted-config' do
  include TransformC::Helpers

  let(:url) { 'https://cal.example.com/crew.ics' }
  let(:mocks) { { url => TransformC.ics_with_events([{ summary: 'Standup', start: '20260909T090000Z', end: '20260909T091500Z' }]) } }

  def board(fields) = TransformC.payload(run_transform(now: '2026-09-09T09:00:00Z', fields: { use_demo_data: 'false' }.merge(fields), mocks:))

  def legend(fields) = board(fields)['legend'].map { it['name'] }

  it 'the Set Up With switch says which box is read' do
    both = { calendar_list: "Fry #{url}\n", config_json: JSON.generate(lines: [{ name: 'Leela' }], calendars: [{ url:, line: 'Leela' }]) }

    expect(legend(both.merge(setup_mode: 'links'))).to eq(['Fry']), 'links mode read the configuration'
    expect(legend(both.merge(setup_mode: 'config'))).to eq(['Leela']), 'config mode read the list'
    # A device from before the switch existed has no answer in it (TransformC::NO_SETUP_MODE stands in for that):
    # the box it always read comes first, the new one is the fallback.
    expect(legend(both)).to eq(['Leela']), 'an older device lost its configuration'
    expect(legend(calendar_list: both[:calendar_list])).to eq(['Fry']), 'an older device did not fall back to the list'
  end

  it 'unreadable text is reported for the box it was read from' do
    list = board(setup_mode: 'links', calendar_list: 'just some words')
    expect(list['board_notice'] || '').to match(/\AThe Calendars setting/), "the list box was not named: #{list['board_notice']}"

    config = board(setup_mode: 'config', config_json: '{ "calendars": [ oops')
    expect(config['board_notice'] || '').to match(/\AThe Configuration setting/),
                                            "the configuration box was not named: #{config['board_notice']}"
  end

  it 'a board builds from a configuration that arrived escaped' do
    escaped = JSON.pretty_generate({ lines: [{ name: 'Fry' }], calendars: [{ url:, name: 'Fry', rules: [{ match: { type: 'any' }, line: 'Fry' }] }] },
                                   indent: ' ').gsub(/([\[\]])/) { "\\#{::Regexp.last_match(1)}" }
    data = board(config_json: escaped)

    expect(data['legend'].map { it['name'] }).to eq(['Fry']), 'the board is not the one the config asked for'
    expect(data['events'].map { it['title'] }).to eq(['Standup']), 'the events did not arrive'
  end
end
