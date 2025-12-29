# frozen_string_literal: true

require "tmpdir"

RSpec.describe Devagent::History do
  it "returns empty history when no file exists" do
    Dir.mktmpdir do |dir|
      history = described_class.new(dir)
      expect(history.entries).to eq([])
    end
  end

  it "deduplicates commands case-insensitively and persists to disk" do
    Dir.mktmpdir do |dir|
      history = described_class.new(dir)
      history.add("bundle exec rspec")
      history.add("BUNDLE exec rspec")
      history.add("  bundle exec rubocop  ")

      expect(history.entries).to eq(["BUNDLE exec rspec", "bundle exec rubocop"])

      # Re-load from disk
      history2 = described_class.new(dir)
      expect(history2.entries).to eq(["BUNDLE exec rspec", "bundle exec rubocop"])
    end
  end

  it "recovers from invalid JSON history" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, Devagent::History::HISTORY_FILENAME)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{not json", encoding: "UTF-8")

      history = described_class.new(dir)
      expect(history.entries).to eq([])
    end
  end
end

