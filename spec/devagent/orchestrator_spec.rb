# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Orchestrator do
  let(:output) { StringIO.new }
  let(:streamer) { instance_double(Devagent::Streamer, say: nil, with_stream: nil) }
  let(:planner) { instance_double(Devagent::Planner) }
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
  let(:tool_bus) { instance_double(Devagent::ToolBus, reset!: nil, invoke: nil, changes_made?: changes_made, run_tests: :ok) }
  let(:tool_registry) do
    instance_double(
      Devagent::ToolRegistry,
      tools_for_phase: { "fs_read" => double(name: "fs_read", description: "read"),
                         "fs_write" => double(name: "fs_write", description: "write") },
      fetch: double(allowed_phases: %i[execution])
    )
  end
  let(:changes_made) { true }

  before do
    allow(Devagent::Streamer).to receive(:new).and_return(streamer)
    allow(Devagent::Planner).to receive(:new).and_return(planner)
    allow(context).to receive(:tool_bus).and_return(tool_bus)
  end

  describe "#run" do
    let(:plan) do
      Devagent::Plan.new(
        summary: "Do work",
        actions: [
          { "type" => "fs_read", "args" => { "path" => "file" } },
          { "type" => "fs_write", "args" => { "path" => "file", "content" => "text" } }
        ],
        confidence: 0.8
      )
    end

    before do
      allow(planner).to receive(:plan).and_return(plan)
    end

    it "executes a plan and runs tests when changes are made" do
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("build feature")

      expect(session_memory).to have_received(:append).with("user", "build feature")
      expect(index).to have_received(:build!)
      expect(tool_bus).to have_received(:reset!).once
      expect(tool_bus).to have_received(:invoke).with(plan.actions.first)
      expect(tool_bus).to have_received(:invoke).with(plan.actions.last)
      expect(tool_bus).to have_received(:run_tests)
      expect(planner).to have_received(:plan).once
    end

    it "stops early when plan has no actions" do
      allow(planner).to receive(:plan).and_return(Devagent::Plan.new(summary: "noop", actions: [], confidence: 0.1))
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("no work")

      expect(tool_bus).not_to have_received(:invoke)
      expect(tool_bus).not_to have_received(:run_tests)
    end

    it "replans when tests fail" do
      allow(tool_bus).to receive(:run_tests).and_return(:failed)
      allow(tool_bus).to receive(:changes_made?).and_return(true)
      allow(planner).to receive(:plan).and_return(plan, plan)
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("iterate")

      expect(planner).to have_received(:plan).twice
      expect(session_memory).to have_received(:append).with("assistant", include("Tests failed")).at_least(:once)
      expect(tracer).to have_received(:event).with("tests_failed").at_least(:once)
    end

    it "skips tests when no changes occur" do
      allow(tool_bus).to receive(:changes_made?).and_return(false)
      orchestrator = described_class.new(context, output: output)

      orchestrator.run("noop")

      expect(tool_bus).not_to have_received(:run_tests)
      expect(streamer).to have_received(:say).with(include("No changes"))
    end
  end
end
