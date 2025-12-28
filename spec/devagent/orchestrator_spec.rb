# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Orchestrator do
  let(:output) { StringIO.new }
  let(:streamer) { instance_double(Devagent::Streamer, say: nil, with_stream: nil) }
  let(:planner) { instance_double(Devagent::Planner) }
  let(:classifier) { instance_double(Devagent::IntentClassifier) }
  let(:context) do
    instance_double(
      Devagent::Context,
      session_memory: session_memory,
      index: index,
      tracer: tracer,
      tool_registry: tool_registry,
      tool_bus: tool_bus,
      config: { "auto" => { "max_iterations" => 2, "require_tests_green" => true } },
      plugins: []
    )
  end
  let(:session_memory) { instance_double(Devagent::SessionMemory, append: nil) }
  let(:index) { instance_double(Devagent::EmbeddingIndex, build!: nil) }
  let(:tracer) { instance_double(Devagent::Tracer, event: nil) }
  let(:tool_bus) do
    instance_double(
      Devagent::ToolBus,
      reset!: nil,
      invoke: nil,
      read_file: "",
      changes_made?: changes_made,
      run_tests: :ok
    )
  end
  let(:tool_registry) do
    instance_double(
      Devagent::ToolRegistry,
      tools_for_phase: {
        "fs_read" => double(name: "fs_read", description: "read"),
        "fs_write_diff" => double(name: "fs_write_diff", description: "write diff")
      },
      fetch: double(allowed_phases: %i[execution])
    )
  end
  let(:changes_made) { true }

  before do
    allow(Devagent::Streamer).to receive(:new).and_return(streamer)
    allow(Devagent::Planner).to receive(:new).and_return(planner)
    allow(Devagent::IntentClassifier).to receive(:new).and_return(classifier)
    allow(classifier).to receive(:classify).and_return({ "intent" => "CODE_EDIT", "confidence" => 0.9 })
    allow(context).to receive(:tool_bus).and_return(tool_bus)
  end

  describe "#run" do
    let(:plan) do
      Devagent::Plan.new(
        plan_id: "test-plan",
        goal: "Do work",
        assumptions: [],
        steps: [
          { "step_id" => 1, "action" => "fs_read", "path" => "file", "command" => nil, "reason" => "read", "depends_on" => [0] },
          { "step_id" => 2, "action" => "fs_write", "path" => "file", "command" => nil, "reason" => "write", "depends_on" => [1] }
        ],
        success_criteria: ["tests pass"],
        rollback_strategy: "revert",
        confidence: 0.8
      )
    end

    before do
      allow(planner).to receive(:plan).and_return(plan)
      allow(Devagent::DecisionEngine).to receive(:new).and_return(instance_double(Devagent::DecisionEngine, decide: { "decision" => "SUCCESS", "reason" => "ok", "confidence" => 0.9 }))
    end

    it "executes a plan and runs tests when changes are made" do
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("build feature")

      expect(session_memory).to have_received(:append).with("user", "build feature")
      expect(index).to have_received(:build!)
      expect(tool_bus).to have_received(:reset!).once
      expect(tool_bus).to have_received(:invoke).with("type" => "fs_read", "args" => { "path" => "file" })
      expect(tool_bus).to have_received(:invoke).with("type" => "fs_write_diff", "args" => hash_including("path" => "file"))
      expect(tool_bus).to have_received(:run_tests)
      expect(planner).to have_received(:plan).once
    end

    it "stops early when plan has no actions" do
      allow(planner).to receive(:plan).and_return(Devagent::Plan.new(plan_id: "p", goal: "noop", assumptions: ["impossible"], steps: [], success_criteria: [], rollback_strategy: "", confidence: 0.9))
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("no work")

      expect(tool_bus).not_to have_received(:invoke)
      expect(tool_bus).not_to have_received(:run_tests)
    end

    it "replans when tests fail" do
      allow(tool_bus).to receive(:run_tests).and_return(:failed)
      allow(tool_bus).to receive(:changes_made?).and_return(true)
      allow(planner).to receive(:plan).and_return(plan, plan)
      allow(Devagent::DecisionEngine).to receive(:new).and_return(instance_double(Devagent::DecisionEngine, decide: { "decision" => "RETRY", "reason" => "tests failing", "confidence" => 0.8 }))
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("iterate")

      expect(planner).to have_received(:plan).twice
      expect(tracer).to have_received(:event).with("tests_failed").at_least(:once)
    end

    it "skips tests when no changes occur" do
      allow(tool_bus).to receive(:changes_made?).and_return(false)
      allow(Devagent::DecisionEngine).to receive(:new).and_return(instance_double(Devagent::DecisionEngine, decide: { "decision" => "SUCCESS", "reason" => "ok", "confidence" => 0.9 }))
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("noop")

      expect(tool_bus).not_to have_received(:run_tests)
      expect(streamer).to have_received(:say).with(include("No changes"))
    end

    it "does not run tools for EXPLANATION intent" do
      allow(classifier).to receive(:classify).and_return({ "intent" => "EXPLANATION", "confidence" => 0.9 })
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("Explain Ruby blocks")

      expect(index).not_to have_received(:build!)
      expect(tool_bus).not_to have_received(:invoke)
      expect(tool_bus).not_to have_received(:run_tests)
    end
  end
end
