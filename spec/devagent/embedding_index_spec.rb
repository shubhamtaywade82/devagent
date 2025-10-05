# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::EmbeddingIndex do
  class FakeEmbeddingAdapter
    def initialize(dimension)
      @dimension = dimension
    end

    def embed(texts, model: nil)
      Array(texts).map { Array.new(@dimension, 0.1) }
    end
  end

  class StubEmbeddingContext
    attr_accessor :provider, :model, :adapter

    def initialize(provider:, dimension: 3)
      @provider = provider
      @model = "model"
      @adapter = FakeEmbeddingAdapter.new(dimension)
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
  end

  let(:repo) { Dir.mktmpdir }
  let(:logger_messages) { [] }

  before do
    File.write(File.join(repo, "sample.rb"), "class Sample\nend\n")
  end

  after do
    FileUtils.remove_entry(repo)
  end

  it "persists embedding metadata and rebuilds when provider changes" do
    context = StubEmbeddingContext.new(provider: "openai", dimension: 4)
    index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
    index.build!

    expect(index.metadata["dim"]).to eq(4)

    context.provider = "ollama"
    context.adapter = FakeEmbeddingAdapter.new(2)
    rebuilt_index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
    rebuilt_index.build!

    expect(logger_messages.any? { |msg| msg.include?("Embedding backend changed") }).to be(true)
    expect(rebuilt_index.metadata["dim"]).to eq(2)
  end

  it "clears the store when embedding dimensions change" do
    context = StubEmbeddingContext.new(provider: "openai", dimension: 4)
    index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
    index.build!

    context.adapter = FakeEmbeddingAdapter.new(6)
    rebuilt_index = described_class.new(repo, {}, context: context, logger: ->(msg) { logger_messages << msg })
    expect(rebuilt_index.store).to receive(:clear!).at_least(:once).and_call_original

    rebuilt_index.build!

    expect(rebuilt_index.metadata["dim"]).to eq(6)
  end
end
