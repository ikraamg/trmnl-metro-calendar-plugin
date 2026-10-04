# frozen_string_literal: true

require_relative '../support/transform_c'

# Ported from test/trmnl/transform/tasks.spec.js.
RSpec.describe 'tasks' do
  include TransformC::Helpers

  let(:feed) do
    todos = [
      todo('Mow the lawn'), # no due date at all
      todo('Bins out', ['DUE:20260915T170000Z']), # due later today
      todo('Library books', ['DUE:20260914T170000Z']), # still owed from yesterday
      todo('Homework', ['DUE:20260915T060000Z', 'STATUS:COMPLETED', 'COMPLETED:20260915T063000Z']),
      todo('Old chore', ['DUE:20260914T060000Z', 'STATUS:COMPLETED', 'COMPLETED:20260914T070000Z']),
      todo('Never mind', ['STATUS:CANCELLED'])
    ]
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n#{todos.join("\r\n")}\r\nEND:VCALENDAR\r\n"
  end

  def todo(summary, lines = [])
    ['BEGIN:VTODO', "UID:#{summary}", 'DTSTAMP:20260915T000000Z', "SUMMARY:#{summary}", *lines, 'END:VTODO'].join("\r\n")
  end

  def board(extra = {})
    config = JSON.generate(lines: [{ name: 'Alex' }], calendars: [{ url: 'https://example.com/tasks.ics', name: 'Alex' }])
    TransformC.payload(run_transform(now: '2026-09-15T08:00:00Z', fields: { config_json: config }.merge(extra),
                                     mocks: { '*' => feed }, time_zone: 'Europe/Brussels'))
  end

  it 'a task with a time is a stop; one without, and one still owed, are tasks' do
    data = board
    tasks = data['tasks'] || []
    stops = data['events'].select { it['todo'] }.map { it['title'] }.sort
    owed = tasks.map { "#{it['title']}#{' (done)' if it['done']}#{' (overdue)' if it['overdue']}" }.sort

    expect(stops.join(',')).to eq('Bins out,Homework'), "the stops: #{stops.join(',')}"
    expect(owed.join(' | ')).to eq('Library books (overdue) | Mow the lawn'), "what is owed: #{owed.join(' | ')}"
    # done today keeps its stop and says so; done yesterday is gone; cancelled never was
    expect(data['events'].select { it['todo'] && it['done'] }.map { it['title'] }.join(',')).to eq('Homework'), 'ticked stops'
    expect(data['events'].map { it['title'] }).not_to include(/Old chore|Never mind/), 'a finished or cancelled task came back'
    expect(tasks.map { it['title'] }).not_to include(/Old chore|Never mind/), 'a finished or cancelled task is owed'
    # every task knows whose it is
    expect(tasks.map { (it['owners'] || []).length }).to all(eq(1)), "a task with no owner: #{tasks}"
  end

  it 'the setting takes them off the board, and says how many wait at each end' do
    off = board(tasks_count: 'hide')
    expect(off['tasks'] || []).to be_empty, "tasks with the setting off: #{off['tasks']}"
    # two each by default, one each when asked
    two = board
    expect(two['tasks'].length).to eq(2), "by default: #{two['tasks'].map { it['title'] }}"
    one = board(tasks_count: '1')
    expect(one['tasks'].map { it['title'] }).to eq(['Library books']), "one each: #{one['tasks'].map { it['title'] }}"
  end
end
