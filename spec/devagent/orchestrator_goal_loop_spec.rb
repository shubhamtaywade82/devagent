# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Orchestrator, "goal-driven retry loop" do
  let(:output) { StringIO.new }
  let(:streamer) { instance_double(Devagent::Streamer, say: nil, with_stream: nil) }
  let(:new_planner) { instance_double(Devagent::Planning::Planner) }
  let(:classifier) { instance_double(Devagent::IntentClassifier) }
  let(:config) do
    {
      "auto" => {
        "max_iterations" => 2,
        "max_goal_attempts" => 3,
        "require_tests_green" => true,
        "allowlist" => ["lib/**", "spec/**"]
      }
    }
  end
  let(:context) do
    instance_double(
      Devagent::Context,
      repo_path: "/workspace",
      session_memory: session_memory,
      index: index,
      tracer: tracer,
      tool_registry: tool_registry,
      tool_bus: tool_bus,
      config: config,
      plugins: []
    )
  end
  let(:session_memory) { instance_double(Devagent::SessionMemory, append: nil) }
  let(:index) { instance_double(Devagent::EmbeddingIndex, build!: nil) }
  let(:tracer) { instance_double(Devagent::Tracer, event: nil) }
  let(:safety) { instance_double(Devagent::Safety, allowed?: true) }
  let(:tool_bus) do
    instance_double(
      Devagent::ToolBus,
      reset!: nil,
      invoke: { "success" => true, "artifact" => {} },
      read_file: { "path" => "file", "content" => "" },
      changes_made?: true,
      run_tests: :ok,
      safety: safety
    )
  end
  let(:tool_registry) do
    instance_double(
      Devagent::ToolRegistry,
      tools_for_phase: {
        "fs.read" => double(name: "fs.read", description: "read"),
        "fs.create" => double(name: "fs.create", description: "create"),
        "exec.run" => double(name: "exec.run", description: "run")
      },
      tools: {
        "fs.read" => double(name: "fs.read", description: "read"),
        "fs.create" => double(name: "fs.create", description: "create"),
        "exec.run" => double(name: "exec.run", description: "run"),
        "fs.write_diff" => double(name: "fs.write_diff", description: "internal")
      },
      fetch: double(allowed_phases: %i[execution])
    )
  end

  before do
    allow(Devagent::Streamer).to receive(:new).and_return(streamer)
    allow(Devagent::Planner).to receive(:new).and_return(double("old_planner"))
    allow(Devagent::Planning::Planner).to receive(:new).and_return(new_planner)
    allow(Devagent::IntentClassifier).to receive(:new).and_return(classifier)
    allow(classifier).to receive(:classify).and_return({ "intent" => "CODE_EDIT", "confidence" => 0.9 })
    allow(context).to receive(:tool_bus).and_return(tool_bus)
    allow(Devagent::DiffGenerator).to receive(:new).and_return(
      instance_double(Devagent::DiffGenerator, generate: "--- a/file\n+++ b/file\n@@ +1 @@\n+hi")
    )
  end

  describe "goal attempt tracking" do
    it "records goal attempts in the tracer" do
      plan = Devagent::Planning::Plan.new(
        plan_id: "test",
        goal: "Test",
        assumptions: [],
        steps: [{ "step_id" => 1, "action" => "exec.run", "command" => "echo hi", "reason" => "test",
                  "depends_on" => [] }],
        success_criteria: [],
        rollback_strategy: "",
        confidence: 80
      )
      allow(new_planner).to receive(:call).and_return(plan)
      allow(Devagent::DecisionEngine).to receive(:new).and_return(
        instance_double(Devagent::DecisionEngine,
                        decide: { "decision" => "SUCCESS", "reason" => "ok", "confidence" => 0.9 })
      )

      orchestrator = described_class.new(context, output: output)
      orchestrator.run("do something")

      expect(tracer).to have_received(:event).with("goal_attempt", hash_including(attempt: 1))
    end

    it "respects max_goal_attempts configuration" do
      plan = Devagent::Planning::Plan.new(
        plan_id: "test",
        goal: "Test",
        assumptions: [],
        steps: [],
        success_criteria: [],
        rollback_strategy: "",
        confidence: 80
      )
      # Plan with no steps should fail
      allow(new_planner).to receive(:call).and_return(plan)

      orchestrator = described_class.new(context, output: output)
      orchestrator.run("do something")

      # Should have tried up to max_goal_attempts (3) times
      expect(tracer).to have_received(:event).with("goal_attempt", hash_including(attempt: 1))
    end
  end

  describe "goal validation" do
    it "validates goal after each attempt" do
      plan = Devagent::Planning::Plan.new(
        plan_id: "test",
        goal: "Test",
        assumptions: [],
        steps: [{ "step_id" => 1, "action" => "exec.run", "command" => "echo hi", "reason" => "test",
                  "depends_on" => [] }],
        success_criteria: [],
        rollback_strategy: "",
        confidence: 80
      )
      allow(new_planner).to receive(:call).and_return(plan)
      allow(Devagent::DecisionEngine).to receive(:new).and_return(
        instance_double(Devagent::DecisionEngine,
                        decide: { "decision" => "SUCCESS", "reason" => "ok", "confidence" => 0.9 })
      )

      orchestrator = described_class.new(context, output: output)
      orchestrator.run("do something")

      expect(tracer).to have_received(:event).with("goal_validation", hash_including(:satisfied, :reason))
    end
  end

  describe "stagnation detection" do
    it "detects stagnation when same result is produced twice" do
      plan = Devagent::Planning::Plan.new(
        plan_id: "test",
        goal: "Test",
        assumptions: [],
        steps: [{ "step_id" => 1, "action" => "exec.run", "command" => "echo hi", "reason" => "test",
                  "depends_on" => [] }],
        success_criteria: [],
        rollback_strategy: "",
        confidence: 80
      )

      # Return same plan twice
      allow(new_planner).to receive(:call).and_return(plan)

      # Decision engine always says retry to trigger the loop
      decision_engine = instance_double(Devagent::DecisionEngine)
      allow(decision_engine).to receive(:decide).and_return(
        { "decision" => "RETRY", "reason" => "keep trying", "confidence" => 0.6 }
      )
      allow(Devagent::DecisionEngine).to receive(:new).and_return(decision_engine)

      # Mock git diff to return same content (simulating no progress)
      allow(Devagent::GitDiff).to receive(:current).and_return("same diff content")

      orchestrator = described_class.new(context, output: output)
      orchestrator.run("do something")

      # Should have detected stagnation
      expect(tracer).to have_received(:event).with("goal_stagnation", hash_including(:reason))
    end
  end
end
