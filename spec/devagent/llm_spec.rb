# frozen_string_literal: true

RSpec.describe Devagent::LLM do
  let(:ollama_client) { instance_double(Devagent::Ollama::Client) }
  let(:context) { instance_double(Devagent::Context, ollama_client: ollama_client) }

  before do
    allow(context).to receive(:openai_api_key).and_return(nil)
    allow(context).to receive(:llm_cache).and_return({})
    allow(context).to receive(:llm_params) { |_provider| {} }
    allow(context).to receive(:embedding_model_for) { |_role, _provider| nil }
  end

  it "caches adapters per role" do
    cache = {}
    allow(context).to receive(:llm_cache).and_return(cache)
    allow(context).to receive(:provider_for).with(:developer).and_return("ollama")
    allow(context).to receive(:model_for).with(:developer).and_return("qwen")
    allow(described_class).to receive(:build_adapter).and_return(:adapter)

    first = described_class.for_role(context, :developer)
    second = described_class.for_role(context, :developer)

    expect(first).to eq(:adapter)
    expect(second).to eq(:adapter)
    expect(described_class).to have_received(:build_adapter).once
    expect(cache[:developer]).to eq(:adapter)
  end

  it "raises when OpenAI is requested without credentials" do
    allow(context).to receive(:provider_for).with(:planner).and_return("openai")
    allow(context).to receive(:model_for).with(:planner).and_return("gpt-4o-mini")
    allow(context).to receive(:llm_params).with("openai").and_return({})
    allow(context).to receive(:embedding_model_for).with(:planner, "openai").and_return("text-embedding-3-small")
    allow(context).to receive(:llm_cache).and_return({})

    expect {
      described_class.for_role(context, :planner)
    }.to raise_error(Devagent::Error, /OPENAI_API_KEY/)
  end
end
