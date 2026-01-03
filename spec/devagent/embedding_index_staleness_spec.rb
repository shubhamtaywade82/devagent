# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::EmbeddingIndex, "staleness" do
  class FakeStalenessEmbeddingAdapter
    def initialize(dimension)
      @dimension = dimension
    end

    def embed(texts, model: nil)
      Array(texts).map { Array.new(@dimension, 0.1) }
    end
  end

  class StubStalenessContext
    attr_accessor :provider, :model, :adapter

    def initialize(provider:, dimension: 4)
      @provider = provider
      @model = "test-model"
      @adapter = FakeStalenessEmbeddingAdapter.new(dimension)
    end

    def llm_for(_role)
      @adapter
    end

    def model_for(_role)
      @model
    end

    def embedding_backend_info
      { "provider" => provider, "model" => model }
    end

    def respond_to?(method, include_private = false)
      return false if method == :config

      super
    end
  end

  let(:repo) { Dir.mktmpdir }
  let(:logger_messages) { [] }

  before do
    File.write(File.join(repo, "sample.rb"), "class Sample\nend\n")
  end

  after do
    FileUtils.remove_entry(repo)
  end

  describe "#file_stale?" do
    it "returns true for files not in hash cache" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })

      expect(index.file_stale?("sample.rb")).to be true
    end

    it "returns false for files after indexing" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      expect(index.file_stale?("sample.rb")).to be false
    end

    it "returns true when file content changes" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      # Modify the file
      File.write(File.join(repo, "sample.rb"), "class Sample\n  def hello; end\nend\n")

      expect(index.file_stale?("sample.rb")).to be true
    end
  end

  describe "#stale_files" do
    it "returns empty array when index is fresh" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      expect(index.stale_files).to be_empty
    end

    it "returns modified files" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      # Modify the file
      File.write(File.join(repo, "sample.rb"), "class Sample\n  def hello; end\nend\n")

      expect(index.stale_files).to include("sample.rb")
    end

    it "returns new files" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      # Add a new file
      File.write(File.join(repo, "new_file.rb"), "class NewFile; end\n")

      expect(index.stale_files).to include("new_file.rb")
    end
  end

  describe "#any_stale?" do
    it "returns false when index is fresh" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      expect(index.any_stale?).to be false
    end

    it "returns true when files have changed" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      File.write(File.join(repo, "sample.rb"), "class Sample\n  def modified; end\nend\n")

      expect(index.any_stale?).to be true
    end
  end

  describe "#build_incremental!" do
    it "only re-embeds stale files" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      initial_count = index.document_count

      # Add a new file
      File.write(File.join(repo, "new_file.rb"), "class NewFile; end\n")

      # Incremental build should only process new file
      result = index.build_incremental!

      expect(result.size).to be >= 1
      expect(index.document_count).to be > initial_count
    end

    it "skips when no files are stale" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      # No changes - incremental build should return empty
      result = index.build_incremental!
      expect(result).to be_empty
    end
  end

  describe "metadata with indexed_at" do
    it "includes indexed_at timestamp" do
      context = StubStalenessContext.new(provider: "openai", dimension: 4)
      index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
      index.build!

      expect(index.metadata).to have_key("indexed_at")
      expect(index.metadata["indexed_at"]).to match(/\d{4}-\d{2}-\d{2}/)
    end
  end
end
