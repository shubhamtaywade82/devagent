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
end

