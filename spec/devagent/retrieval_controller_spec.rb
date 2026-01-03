# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::RetrievalController do
  let(:repo_path) { Dir.mktmpdir }
  let(:logger_messages) { [] }

  # Minimal context double for testing
  class FakeEmbeddingAdapter
    def initialize(dimension)
      @dimension = dimension
    end

    def embed(texts, model: nil)
      Array(texts).map { Array.new(@dimension, 0.1) }
    end
  end

  class StubContext
    attr_accessor :provider, :model, :adapter, :repo_path, :config, :tracer

    def initialize(repo_path:, dimension: 4)
      @repo_path = repo_path
      @provider = "openai"
      @model = "text-embedding-3-small"
      @adapter = FakeEmbeddingAdapter.new(dimension)
      @config = {
        "index" => {
          "globs" => ["**/*.rb"],
          "chunk_size" => 1800,
          "overlap" => 200
        }
      }
      @tracer = FakeTracer.new
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

    def index
      @index ||= Devagent::EmbeddingIndex.new(
        repo_path,
        config["index"],
        context: self,
        logger: ->(_msg) {}
      )
    end
  end

  class FakeTracer
    attr_reader :events

    def initialize
      @events = []
    end

    def event(name, **data)
      @events << { name: name, data: data }
    end
  end

  let(:context) { StubContext.new(repo_path: repo_path) }
  let(:controller) { described_class.new(context) }

  before do
    # Create a sample file for indexing
    File.write(File.join(repo_path, "sample.rb"), "class Sample\n  def hello\n    puts 'hello'\n  end\nend\n")
  end

  after do
    FileUtils.remove_entry(repo_path)
  end

  describe "#repo_empty?" do
    it "returns true when no documents are indexed" do
      expect(controller.repo_empty?).to be true
    end

    it "returns false after indexing" do
      context.index.build!
      # Need to clear the cached document count
      controller.clear_cache!
      expect(controller.repo_empty?).to be false
    end
  end

  describe "#embeddings_ready?" do
    it "returns false before indexing" do
      expect(controller.embeddings_ready?).to be false
    end

    it "returns true after indexing" do
      context.index.build!
      controller.clear_cache!
      expect(controller.embeddings_ready?).to be true
    end
  end

  describe "#embeddings_stale?" do
    it "returns true when metadata is empty" do
      expect(controller.embeddings_stale?).to be true
    end

    it "returns false when backend matches" do
      context.index.build!
      expect(controller.embeddings_stale?).to be false
    end

    it "returns true when provider changes" do
      context.index.build!
      context.provider = "ollama"
      expect(controller.embeddings_stale?).to be true
    end
  end

  describe "#retrieve_for_goal" do
    before do
      context.index.build!
      controller.clear_cache!
    end

    it "returns files for CODE_EDIT intent" do
      result = controller.retrieve_for_goal("fix the hello method", intent: "CODE_EDIT")
      expect(result[:files]).to be_an(Array)
      expect(result[:skip_reason]).to be_nil
      expect(result[:cached]).to be false
    end

    it "caches results for the same goal" do
      result1 = controller.retrieve_for_goal("fix the hello method", intent: "CODE_EDIT")
      result2 = controller.retrieve_for_goal("fix the hello method", intent: "CODE_EDIT")

      expect(result1[:cached]).to be false
      expect(result2[:cached]).to be true
    end

    it "returns skip_reason :repo_empty when repo is empty" do
      # Clear the index
      context.index.store.clear!
      controller.clear_cache!

      result = controller.retrieve_for_goal("fix something", intent: "CODE_EDIT")
      expect(result[:skip_reason]).to eq(:repo_empty)
    end

    it "returns skip_reason :intent_skipped for EXPLANATION intent" do
      result = controller.retrieve_for_goal("what is this?", intent: "EXPLANATION")
      expect(result[:skip_reason]).to eq(:intent_skipped)
    end
  end

  describe "#retrieved_files_for" do
    before do
      context.index.build!
      controller.clear_cache!
    end

    it "returns empty array when no retrieval has been done" do
      expect(controller.retrieved_files_for("unknown goal")).to eq([])
    end

    it "returns cached files after retrieval" do
      controller.retrieve_for_goal("fix the hello method", intent: "CODE_EDIT")
      files = controller.retrieved_files_for("fix the hello method")
      expect(files).to be_an(Array)
    end
  end

  describe "#index_status" do
    it "returns status information" do
      status = controller.index_status
      expect(status).to have_key(:document_count)
      expect(status).to have_key(:repo_empty)
      expect(status).to have_key(:embeddings_ready)
      expect(status).to have_key(:embeddings_stale)
      expect(status).to have_key(:backend)
    end
  end

  describe "#clear_cache!" do
    it "clears the cache" do
      context.index.build!
      controller.clear_cache!
      controller.retrieve_for_goal("test", intent: "CODE_EDIT")
      expect(controller.cache).not_to be_empty

      controller.clear_cache!
      expect(controller.cache).to be_empty
    end
  end
end
