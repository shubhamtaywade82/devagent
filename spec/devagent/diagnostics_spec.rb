# frozen_string_literal: true

require "stringio"

# rubocop:disable Metrics/BlockLength
RSpec.describe Devagent::Diagnostics do
  subject(:diagnostics) { described_class.new(context, output: output) }

  let(:output) { StringIO.new }
  let(:index) do
    instance_double(Devagent::EmbeddingIndex, build!: nil, document_count: 2, metadata: { "dim" => 1536 })
  end
  let(:plugin) do
    Module.new do
      def self.name
        "Devagent::Plugins::RubyGem"
      end
    end
  end
  let(:context) do
    instance_double(
      Devagent::PluginContext,
      resolved_provider: "ollama",
      plugins: [plugin],
      index: index
    )
  end

  before do
    allow(context).to receive(:model_for).with(:default).and_return("llama2")
    allow(context).to receive(:model_for).with(:planner).and_return("llama2")
    allow(context).to receive(:model_for).with(:developer).and_return("llama2")
    allow(context).to receive(:model_for).with(:reviewer).and_return("llama2")
    allow(context).to receive(:provider_for).and_return("ollama")
    allow(context).to receive(:query).and_return("READY")
    allow(index).to receive(:search).and_return([])
  end

  it "returns true when all checks pass" do
    expect(diagnostics.run).to be(true)

    output.rewind
    text = output.string.gsub(/\e\[[0-9;]*m/, "")
    expect(text).to include("All checks passed")
  end

  it "returns false when a check fails" do
    allow(context).to receive(:query).and_raise(StandardError, "connection refused")

    expect(diagnostics.run).to be(false)

    output.rewind
    text = output.string.gsub(/\e\[[0-9;]*m/, "")
    expect(text).to include("✖ ollama connectivity")
    expect(text).to include("connection refused")
  end
end
# rubocop:enable Metrics/BlockLength
