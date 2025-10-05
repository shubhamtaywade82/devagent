# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::SessionMemory do
  let(:repo) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(repo)
  end

  it "appends turns and truncates to the configured limit" do
    memory = described_class.new(repo, limit: 2)

    memory.append("user", "one")
    memory.append("assistant", "two")
    memory.append("user", "three")

    turns = memory.last_turns

    expect(turns.size).to eq(2)
    expect(turns.map { |t| t["content"] }).to eq(%w[two three])
  end

  it "clears stored history" do
    memory = described_class.new(repo, limit: 2)
    memory.append("user", "hello")

    memory.clear!

    expect(memory.last_turns).to be_empty
  end
end
