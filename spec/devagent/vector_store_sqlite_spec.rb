# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::VectorStoreSqlite do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "store.sqlite3") }

  after do
    FileUtils.remove_entry(dir)
  end

  it "persists and retrieves embeddings" do
    store = described_class.new(path)

    store.upsert_many([
                        { key: "a", embedding: [1.0, 0.0], metadata: { "path" => "a.rb" } },
                        { key: "b", embedding: [0.0, 1.0], metadata: { "path" => "b.rb" } }
                      ])

    nearest = store.similar([0.9, 0.1], limit: 1).first
    expect(nearest.metadata["path"]).to eq("a.rb")

    reloaded = described_class.new(path)
    expect(reloaded.all.size).to eq(2)
  end

  it "clears stored embeddings" do
    store = described_class.new(path)
    store.upsert_many([{ key: "a", embedding: [1, 2], metadata: {} }])

    store.clear!

    expect(store.all).to be_empty
  end
end
