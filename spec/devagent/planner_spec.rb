# frozen_string_literal: true

RSpec.describe Devagent::Planner do
  let(:repo_path) { "/tmp/repo" }
  let(:config) { {} }
  let(:llm) do
    double("LLM", call: ->(_) { { confidence: 0.0, actions: [] }.to_json })
  end
  let(:shell) { double("Shell") }
  let(:index) { instance_double(Devagent::Index, retrieve: []) }
  let(:memory) { instance_double(Devagent::Memory) }
  let(:survey) do
    instance_double(
      Devagent::RepoSurvey,
      summary_text: "Directories: lib/ (library runtime code), spec/ (RSpec tests)"
    )
  end
  let(:ctx) do
    Devagent::PluginContext.new(repo_path, config, llm, shell, index, memory, [], survey)
  end

  it "embeds the repository survey and workflow expectations in the prompt" do
    captured_prompt = nil
    allow(llm).to receive(:call) do |prompt, **|
      captured_prompt = prompt
      { confidence: 0.1, actions: [] }.to_json
    end

    described_class.plan(ctx: ctx, task: "document the workflow")

    expect(captured_prompt).to include("Repository survey:")
    expect(captured_prompt).to include("Directories: lib/ (library runtime code)")
    expect(captured_prompt).to include("Workflow expectations")
  end
end
