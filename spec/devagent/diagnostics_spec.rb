# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Diagnostics do
  let(:output) { StringIO.new }
  let(:index) do
    instance_double(Devagent::Index, build!: nil, retrieve: [], document_count: 2)
  end
  let(:llm) { instance_double(Proc) }
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
      llm: llm
    )
  end

  subject(:diagnostics) { described_class.new(context, output: output) }

  before do
    allow(llm).to receive(:call).and_return("READY")
  end

  it "returns true when all checks pass" do
    expect(diagnostics.run).to eq(true)

    output.rewind
    expect(output.string).to include("All checks passed.")
  end

  it "returns false when a check fails" do
    allow(llm).to receive(:call).and_raise(StandardError, "connection refused")

    expect(diagnostics.run).to eq(false)

    output.rewind
    expect(output.string).to include("FAIL").and include("connection refused")
  end

  it "reports missing model configuration" do
    allow(context).to receive(:config).and_return({})

    expect(diagnostics.run).to eq(false)

    output.rewind
    expect(output.string).to include("LLM model not configured")
  end
end
