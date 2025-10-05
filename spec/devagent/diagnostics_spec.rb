# frozen_string_literal: true

require "stringio"

# rubocop:disable Metrics/BlockLength
RSpec.describe Devagent::Diagnostics do
  subject(:diagnostics) { described_class.new(context, output: output) }

  let(:output) { StringIO.new }
  let(:index) do
    instance_double(Devagent::EmbeddingIndex, build!: nil, document_count: 2)
  end
  let(:llm_adapter) { instance_double("LLMAdapter") }
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
      config: { "model" => "llama2" },
      plugins: [plugin],
      index: index,
      planner_model: "llama2",
      provider: "ollama"
    )
  end

  before do
    allow(context).to receive(:llm).and_return(llm_adapter)
    allow(context).to receive(:provider).with(:default).and_return("ollama")
    allow(context).to receive(:provider).with(:planner).and_return("ollama")
    allow(context).to receive(:provider).with(:embedding).and_return("ollama")
    allow(llm_adapter).to receive(:chat).and_return("READY")
    allow(index).to receive(:search).and_return([])
  end

  it "returns true when all checks pass" do
    expect(diagnostics.run).to be(true)

    output.rewind
    expect(output.string).to include("All checks passed.")
  end

  it "returns false when a check fails" do
    allow(llm_adapter).to receive(:chat).and_raise(StandardError, "connection refused")

    expect(diagnostics.run).to be(false)

    output.rewind
    expect(output.string).to include("FAIL").and include("connection refused")
  end

  it "reports missing model configuration" do
    allow(context).to receive(:config).and_return({})

    expect(diagnostics.run).to be(false)

    output.rewind
    expect(output.string).to include("LLM model not configured")
  end
end
# rubocop:enable Metrics/BlockLength
