# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::Context do
  let(:repo) { Dir.mktmpdir }
  let(:original_key) { ENV.delete("OPENAI_API_KEY") }

  before do
    File.write(File.join(repo, "dummy.rb"), "puts 'hi'\n")
  end

  after do
    ENV["OPENAI_API_KEY"] = original_key
    FileUtils.remove_entry(repo)
  end

  it "selects OpenAI adapter when provider is auto and key present" do
    ENV["OPENAI_API_KEY"] = "sk-test"
    allow(OpenAI::Client).to receive(:new).and_return(double(chat: nil, embeddings: nil))

    context = described_class.build(repo)

    expect(context.provider_for(:planner)).to eq("openai")
    expect(Devagent::LLM::OpenAIAdapter).to receive(:new).and_call_original
    context.llm_for(:planner)
  end

  it "falls back to Ollama adapter when key missing" do
    context = described_class.build(repo)

    expect(context.provider_for(:planner)).to eq("ollama")
    expect(context.llm_for(:planner)).to be_a(Devagent::LLM::OllamaAdapter)
  end

  it "supports hybrid models via overrides" do
    context = described_class.build(repo, { "planner_model" => "gpt-4o", "developer_model" => "gpt-4o-mini" })

    expect(context.model_for(:planner)).to eq("gpt-4o")
    expect(context.model_for(:developer)).to eq("gpt-4o-mini")
  end
end
