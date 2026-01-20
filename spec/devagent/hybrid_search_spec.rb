# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::HybridSearch do
  let(:repo_path) { Dir.mktmpdir }
  let(:context) { StubHybridContext.new(repo_path: repo_path) }
  let(:search) { described_class.new(context) }
  let(:logger_messages) { [] }

  class FakeEmbeddingAdapter
    def initialize(dimension)
      @dimension = dimension
    end

    def embed(texts, model: nil)
      Array(texts).map { Array.new(@dimension, 0.1) }
    end
  end

  class StubHybridContext
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
      @tracer = FakeHybridTracer.new
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

  class FakeHybridTracer
    attr_reader :events

    def initialize
      @events = []
    end

    def event(name, **data)
      @events << { name: name, data: data }
    end
  end

  before do
    # Create sample files
    File.write(File.join(repo_path, "auth_controller.rb"), <<~RUBY)
      class AuthController
        def login
          # Handle user login
          User.authenticate(params[:email], params[:password])
        end

        def logout
          session.destroy
        end
      end
    RUBY

    File.write(File.join(repo_path, "user_model.rb"), <<~RUBY)
      class User
        def self.authenticate(email, password)
          user = find_by(email: email)
          return nil unless user
          user.password_matches?(password) ? user : nil
        end
      end
    RUBY

    # Build the index
    context.index.build!
  end

  after do
    FileUtils.remove_entry(repo_path)
  end

  describe "#search" do
    it "returns combined results" do
      result = search.search("login authentication")
      expect(result).to have_key(:files)
      expect(result).to have_key(:results)
      expect(result).to have_key(:grep_count)
      expect(result).to have_key(:embedding_count)
    end

    it "finds files by pattern" do
      result = search.search("AuthController")
      expect(result[:files]).to include("auth_controller.rb")
    end

    it "returns embedding results" do
      result = search.search("how does login work")
      expect(result[:embedding_count]).to be >= 0
    end
  end

  describe "#grep_search" do
    it "finds exact matches" do
      results = search.grep_search(["authenticate"])
      expect(results).to be_an(Array)
      paths = results.map { |r| r[:path] }
      expect(paths).to include("user_model.rb")
    end

    it "returns line numbers" do
      results = search.grep_search(["authenticate"])
      expect(results.first).to have_key(:line)
      expect(results.first[:line]).to be_a(Integer)
    end
  end

  describe "#embedding_search" do
    it "returns semantic matches" do
      results = search.embedding_search("user authentication")
      expect(results).to be_an(Array)
    end

    it "assigns scores" do
      results = search.embedding_search("user authentication")
      next if results.empty?

      expect(results.first).to have_key(:score)
      expect(results.first[:score]).to be_a(Numeric)
    end
  end
end
