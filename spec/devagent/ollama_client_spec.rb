# frozen_string_literal: true

RSpec.describe Devagent::Ollama::Client do
  it "applies configured read timeout" do
    client = described_class.new("host" => "http://localhost:11434", "timeout" => 12)
    http = client.send(:build_http)
    expect(http.read_timeout).to eq(12)
  end
end

