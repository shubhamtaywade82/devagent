# frozen_string_literal: true

RSpec.describe Devagent::Ollama do
  let(:response_body) { { "response" => "All good" }.to_json }
  let(:http_response) { instance_double(Net::HTTPResponse, body: response_body) }

  before do
    allow(described_class).to receive(:perform_request).and_return(http_response)
    allow(described_class).to receive(:ensure_success!)
  end

  it "does not emit debug logging by default" do
    allow(described_class).to receive(:debug_mode?).and_return(false)

    expect do
      described_class.query("Hello", model: "test")
    end.not_to output.to_stdout

    expect do
      described_class.query("Hello", model: "test")
    end.not_to output.to_stderr
  end

  it "emits debug lines when DEVAGENT_DEBUG_LLM is truthy" do
    allow(described_class).to receive(:debug_mode?).and_return(true)

    expect do
      described_class.query("Hello", model: "test")
    end.to output(/\[Ollama\] Prompt:/).to_stderr
  end
end
