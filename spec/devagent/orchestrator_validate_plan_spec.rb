# frozen_string_literal: true

RSpec.describe Devagent::Orchestrator do
  let(:context) do
    instance_double(
      Devagent::Context,
      repo_path: "/workspace"
    )
  end

  let(:orchestrator) { described_class.new(context, output: StringIO.new) }

  let(:visible_tools) do
    [
      double(name: "fs.read"),
      double(name: "fs.write"),
      double(name: "fs.create"),
      double(name: "exec.run")
    ]
  end

  def build_plan(steps:, confidence: 0.8)
    Devagent::Plan.new(
      plan_id: "p",
      goal: "g",
      assumptions: [],
      steps: steps,
      success_criteria: [],
      rollback_strategy: "none",
      confidence: confidence
    )
  end

  it "rejects fs.read on a non-existent file with FILE_MISSING observation" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.read", "path" => "spec/definitely_missing___123.rb", "reason" => "read", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /fs\.read on non-existent file/i)

    expect(state.observations).to include(hash_including("type" => "FILE_MISSING", "path" => "spec/definitely_missing___123.rb"))
  end

  it "rejects fs.write on a non-existent file (must use fs.create)" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.write", "path" => "spec/definitely_missing___456.rb", "reason" => "write", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /fs\.write cannot create new files/i)
  end

  it "accepts fs.create for a non-existent file" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.create", "path" => "spec/definitely_missing___789.rb", "content" => "puts 'hi'\n", "reason" => "create", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.not_to raise_error
  end

  it "rejects repeating the same valid plan (fingerprint hard-stop)" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.read", "path" => "lib/devagent/version.rb", "reason" => "read", "depends_on" => [] }
      ]
    )

    orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /plan repeated without progress/i)
  end

  it "rejects low confidence plans for non-read-only, non-command work" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      confidence: 0.4,
      steps: [
        { "step_id" => 1, "action" => "fs.read", "path" => "lib/devagent/version.rb", "reason" => "read", "depends_on" => [] },
        { "step_id" => 2, "action" => "fs.write", "path" => "lib/devagent/version.rb", "reason" => "write", "depends_on" => [1] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /confidence too low/i)
  end

  it "allows low confidence for read-only plans" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      confidence: 0.3,
      steps: [
        { "step_id" => 1, "action" => "fs.read", "path" => "lib/devagent/version.rb", "reason" => "read", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.not_to raise_error
  end

  it "rejects plans that reference unknown tools" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.nope", "path" => nil, "command" => nil, "reason" => "nope", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /unknown tools/i)
  end

  it "rejects too many reads in the first plan" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.read", "path" => "lib/devagent/version.rb", "reason" => "read", "depends_on" => [] },
        { "step_id" => 2, "action" => "fs.read", "path" => "lib/devagent/version.rb", "reason" => "read again", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /too many reads/i)
  end

  it "rejects fs.create when the target already exists" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.create", "path" => "lib/devagent/version.rb", "content" => "x", "reason" => "create", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /target already exists/i)
  end

  it "rejects fs.write without a prior fs.read dependency (and does not record fingerprints)" do
    state = Devagent::AgentState.initial(goal: "t")
    plan = build_plan(
      steps: [
        { "step_id" => 1, "action" => "fs.read", "path" => "lib/devagent/version.rb", "reason" => "read", "depends_on" => [] },
        { "step_id" => 2, "action" => "fs.write", "path" => "lib/devagent/version.rb", "reason" => "write", "depends_on" => [] }
      ]
    )

    expect do
      orchestrator.send(:validate_plan!, state, plan, visible_tools: visible_tools)
    end.to raise_error(Devagent::Error, /must depend_on prior fs\.read/i)

    expect(state.plan_fingerprints).to be_empty
  end
end

