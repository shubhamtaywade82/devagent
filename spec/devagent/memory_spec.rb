# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::Memory do
  let(:repo) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(repo)
  end

  it "persists values to disk" do
    mem = described_class.new(repo)
    mem.set("k", "v")

    mem2 = described_class.new(repo)
    expect(mem2.get("k")).to eq("v")
  end

  it "deletes keys and persists" do
    mem = described_class.new(repo)
    mem.set("k", "v")
    expect(mem.delete("k")).to eq("v")

    mem2 = described_class.new(repo)
    expect(mem2.get("k")).to be_nil
  end

  it "recovers from invalid json store" do
    dir = File.join(repo, ".devagent")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "memory.json"), "{ not-json")

    mem = described_class.new(repo)
    expect(mem.all).to eq({})
  end
end
