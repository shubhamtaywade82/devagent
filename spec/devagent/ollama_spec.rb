# frozen_string_literal: true

RSpec.describe Devagent::Ollama::Client do
  class FakeHTTPSuccess < Net::HTTPSuccess
    attr_accessor :body
  end

  let(:http) { instance_double(Net::HTTP) }
  let(:client) { described_class.new({ "host" => "http://localhost:11434", "params" => {} }) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:read_timeout=)
  end

  it "returns the generated response text" do
    response = FakeHTTPSuccess.new("1.1", "200", "OK")
    response.body = { "response" => "All good" }.to_json

    captured_request = nil
    allow(http).to receive(:request) do |req|
      captured_request = req
      response
    end

    result = client.generate(prompt: "Hello", model: "test", params: {})

    expect(result).to eq("All good")
    expect(captured_request).to be_a(Net::HTTP::Post)
    expect(captured_request.path).to eq("/api/generate")
  end

  it "returns embedding vectors" do
    response = FakeHTTPSuccess.new("1.1", "200", "OK")
    response.body = { "embedding" => [0.1, 0.2, 0.3] }.to_json

    captured_request = nil
    allow(http).to receive(:request) do |req|
      captured_request = req
      response
    end

    result = client.embed(prompt: "Hello", model: "test")

    expect(result).to eq([0.1, 0.2, 0.3])
    expect(captured_request).to be_a(Net::HTTP::Post)
    expect(captured_request.path).to eq("/api/embeddings")
  end
end
