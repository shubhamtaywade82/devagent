# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::Planning::Planner do
  let(:repo_path) { Dir.mktmpdir }
  let(:context) { StubPlannerContext.new(repo_path: repo_path) }
  let(:retrieval_controller) { FakeRetrievalController.new }

  class FakePlannerEmbeddingAdapter
    def embed(texts, model: nil)
      Array(texts).map { Array.new(4, 0.1) }
    end
  end

  class FakePlannerLLMAdapter
    def initialize(response)
      @response = response
    end

    def query(_prompt, params: {}, response_format: nil)
      @response
    end
  end

  class StubPlannerContext
    attr_accessor :config, :tracer, :llm_cache, :repo_path

    def initialize(repo_path:, llm_response: nil)
      @repo_path = repo_path
      @config = {
        "planner_model" => "test-model",
        "index" => {
          "globs" => ["**/*.rb"],
          "chunk_size" => 1800,
          "overlap" => 200
        }
      }
      @tracer = FakePlannerTracer.new
      @llm_cache = {}
      @llm_response = llm_response || default_response
    end

    def query(role:, prompt:, stream: false, params: {}, response_format: nil)
      @llm_response
    end

    def provider_for(_role)
      "ollama"
    end

    def model_for(_role)
      "test-model"
    end

    def llm_for(_role)
      FakePlannerEmbeddingAdapter.new
    end

    def embedding_backend_info
      { "provider" => "ollama", "model" => "test-model" }
    end

    def index
      @index ||= Devagent::EmbeddingIndex.new(
        repo_path,
        config["index"],
        context: self,
        logger: ->(_msg) {}
      )
    end

    private

    def default_response
      {
        "confidence" => 70,
        "steps" => [
          { "step_id" => 1, "action" => "fs.read", "path" => "sample.rb", "reason" => "Read file", "depends_on" => [] }
        ],
        "blockers" => []
      }.to_json
    end
  end

  class FakePlannerTracer
    attr_reader :events

    def initialize
      @events = []
    end

    def event(name, **data)
      @events << { name: name, data: data }
    end
  end

  class FakeRetrievalController
    attr_accessor :repo_empty_value, :retrieval_result

    def initialize
      @repo_empty_value = false
      @retrieval_result = {
        files: ["sample.rb"],
        snippets: [{ "path" => "sample.rb", "text" => "class Sample; end" }],
        skip_reason: nil,
        cached: false
      }
    end

    def repo_empty?
      @repo_empty_value
    end

    def retrieve_for_goal(_goal, intent:, limit: 8)
      @retrieval_result
    end
  end

  before do
    File.write(File.join(repo_path, "sample.rb"), "class Sample\nend\n")
    context.index.build!
  end

  after do
    FileUtils.remove_entry(repo_path)
  end

  describe "#call with retrieval" do
    it "passes intent to retrieval controller" do
      planner = described_class.new(
        repo_path: repo_path,
        context: context,
        retrieval_controller: retrieval_controller
      )

      plan = planner.call("fix the sample file", intent: "CODE_EDIT")
      expect(plan).to be_a(Devagent::Planning::Plan)
    end

    it "includes retrieved files in the plan" do
      planner = described_class.new(
        repo_path: repo_path,
        context: context,
        retrieval_controller: retrieval_controller
      )

      plan = planner.call("fix the sample file", intent: "CODE_EDIT")
      expect(plan.retrieved_files).to include("sample.rb")
    end

    it "skips retrieval for empty repos" do
      retrieval_controller.repo_empty_value = true
      retrieval_controller.retrieval_result = {
        files: [],
        snippets: [],
        skip_reason: :repo_empty,
        cached: false
      }

      planner = described_class.new(
        repo_path: repo_path,
        context: context,
        retrieval_controller: retrieval_controller
      )

      plan = planner.call("create a new file", intent: "CODE_EDIT")
      expect(plan.retrieved_files).to be_empty
    end
  end

  describe "plan validation with retrieved files" do
    it "includes retrieved files in plan" do
      planner = described_class.new(
        repo_path: repo_path,
        context: context,
        retrieval_controller: retrieval_controller
      )

      plan = planner.call("read sample.rb", intent: "CODE_EDIT")
      expect(plan.path_in_retrieved?("sample.rb")).to be true
    end
  end
end
