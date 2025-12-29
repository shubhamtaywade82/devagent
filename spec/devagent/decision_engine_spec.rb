# frozen_string_literal: true

RSpec.describe Devagent::DecisionEngine do
  let(:context) { instance_double(Devagent::Context) } # no query/provider_for => heuristic path

  subject(:engine) { described_class.new(context) }

  it "retries when tests fail" do
    decision = engine.decide(
      plan: { "success_criteria" => ["tests pass"] },
      step_results: {},
      observations: [{ "type" => "TEST_RESULT", "status" => "FAIL" }]
    )
    expect(decision).to include("decision" => "RETRY")
  end

  it "succeeds when there are no success criteria" do
    decision = engine.decide(
      plan: { "success_criteria" => [] },
      step_results: {},
      observations: []
    )
    expect(decision).to include("decision" => "SUCCESS")
  end

  it "succeeds when tests pass" do
    decision = engine.decide(
      plan: { "success_criteria" => ["tests pass"] },
      step_results: {},
      observations: [{ "type" => "TEST_RESULT", "status" => "PASS" }]
    )
    expect(decision).to include("decision" => "SUCCESS")
  end

  it "uses the reviewer model when context supports structured queries" do
    llm_context = instance_double(
      Devagent::Context,
      provider_for: "openai",
      query: { "decision" => "SUCCESS", "reason" => "ok", "confidence" => 0.9 }.to_json,
      tracer: instance_double(Devagent::Tracer, event: nil)
    )
    llm_engine = described_class.new(llm_context)

    decision = llm_engine.decide(
      plan: { "success_criteria" => ["tests pass"] },
      step_results: {},
      observations: []
    )

    expect(decision).to include("decision" => "SUCCESS", "reason" => "ok")
  end

  it "falls back to heuristic when the model output is invalid" do
    llm_context = instance_double(
      Devagent::Context,
      provider_for: "openai",
      query: "not json",
      tracer: instance_double(Devagent::Tracer, event: nil)
    )
    llm_engine = described_class.new(llm_context)

    decision = llm_engine.decide(
      plan: { "success_criteria" => [] },
      step_results: {},
      observations: []
    )

    expect(decision).to include("decision" => "SUCCESS")
  end
end

