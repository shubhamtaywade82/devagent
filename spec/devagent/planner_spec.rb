# frozen_string_literal: true

RSpec.describe Devagent::Planner do
  subject(:planner) { described_class.new(context, streamer: streamer) }

  let(:tokens) { [] }
  let(:streamer) do
    instance_double(Devagent::Streamer).tap do |dbl|
      allow(dbl).to receive(:with_stream) do |role, &block|
        block.call(->(token) { tokens << token })
        plan_json
      end
    end
  end
  let(:index) { instance_double(Devagent::EmbeddingIndex, retrieve: []) }
  let(:session_memory) { instance_double(Devagent::SessionMemory, last_turns: []) }
  let(:tool_registry) do
    double(tools: {
             "fs_write" => double(name: "fs_write", description: "write", handler: :write_file)
           })
  end
  let(:context) do
    instance_double(
      Devagent::Context,
      index: index,
      session_memory: session_memory,
      plugins: [],
      tool_registry: tool_registry,
      tracer: instance_double(Devagent::Tracer, event: nil)
    )
  end

  let(:plan_json) do
    {
      "plan_id" => "test-plan",
      "goal" => "Ship feature",
      "assumptions" => ["Repo is writable"],
      "steps" => [
        { "step_id" => 1, "action" => "fs_read", "path" => "README.md", "command" => nil, "reason" => "Inspect existing docs", "depends_on" => [0] },
        { "step_id" => 2, "action" => "fs_write", "path" => "README.md", "command" => nil, "reason" => "Update docs", "depends_on" => [1] }
      ],
      "success_criteria" => ["README updated"],
      "rollback_strategy" => "Revert the README changes",
      "confidence" => 0.9
    }.to_json
  end

  let(:review_json) do
    { "approved" => true, "issues" => [] }.to_json
  end

  before do
    allow(context).to receive(:provider_for).with(:planner).and_return("openai")
    allow(context).to receive(:provider_for).with(:reviewer).and_return("openai")
    allow(context).to receive(:provider_for).with(:embedding).and_return("openai")
    allow(context).to receive(:provider_for).and_return("openai")
    allow(context).to receive(:query) do |role:, **kwargs, &block|
      if role == :planner
        %w[{ plan }].each { |token| block&.call(token) }
        plan_json
      else
        review_json
      end
    end
  end

  it "returns a validated plan" do
    plan = planner.plan("Ship feature")

    expect(plan.confidence).to eq(0.9)
    expect(plan.goal).to eq("Ship feature")
    expect(plan.steps.length).to eq(2)
    expect(plan.success_criteria).to include("README updated")
    expect(streamer).to have_received(:with_stream).with(:planner)
    expect(tokens).to include("{")
  end

  it "replans once when reviewer finds issues" do
    attempts = 0
    allow(context).to receive(:query) do |role:, **kwargs, &block|
      if role == :planner
        attempts += 1
        %w[{ plan }].each { |token| block&.call(token) }
        plan_json
      else
        attempts == 1 ? { "approved" => false, "issues" => ["Add tests"] }.to_json : review_json
      end
    end

    plan = planner.plan("Ship feature")
    expect(plan.actions).not_to be_empty
    expect(attempts).to eq(2)
  end
end
