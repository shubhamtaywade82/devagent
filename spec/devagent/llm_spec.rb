# frozen_string_literal: true

RSpec.describe Devagent::LLM do
  let(:ollama_client) { instance_double(Devagent::Ollama::Client) }
  let(:config) do
    {
      "model" => "qwen",
      "openai" => {
        "uri_base" => "https://api.openai.com/v1",
        "api_key_env" => "OPENAI_API_KEY",
        "params" => {}
      },
      "ollama" => { "params" => {} }
    }
  end
  let(:context) do
    instance_double(
      Devagent::Context,
      config: config,
      ollama_client: ollama_client
    )
  end

  before do
    allow(context).to receive_messages(openai_api_key: nil, llm_cache: {})
    allow(context).to receive(:model_for) { |role| role == :embedding ? "text-embedding-3-small" : "qwen" }
    allow(context).to receive(:llm_params).and_return({})
  end

  it "caches adapters per role" do
    cache = {}
    allow(context).to receive(:llm_cache).and_return(cache)
    allow(context).to receive(:provider_for).with(:developer).and_return("ollama")
    allow(described_class).to receive(:adapter_for).and_return(:adapter)

    first = described_class.for_role(context, :developer)
    second = described_class.for_role(context, :developer)

    expect(first).to eq(:adapter)
    expect(second).to eq(:adapter)
    expect(described_class).to have_received(:adapter_for).once
    expect(cache[:developer]).to eq(:adapter)
  end

  it "raises when OpenAI is requested without credentials" do
    allow(context).to receive(:provider_for).with(:planner).and_return("openai")

    expect do
      described_class.for_role(context, :planner)
    end.to raise_error(Devagent::Error, /Set OPENAI_API_KEY or configure openai\.uri_base for Ollama/)
  end
end
