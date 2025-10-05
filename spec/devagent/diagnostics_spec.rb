# frozen_string_literal: true

require "stringio"

# rubocop:disable Metrics/BlockLength
RSpec.describe Devagent::Diagnostics do
  subject(:diagnostics) { described_class.new(context, output: output) }

  let(:output) { StringIO.new }
  let(:index) do
    instance_double(Devagent::Index, build!: nil, search: [], document_count: 2)
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
      config: { "model" => "llama2" },
      plugins: [plugin],
      index: index,
      chat: "READY"
    )
  end

  before do
    allow(context).to receive(:chat).and_return("READY")
  end

  it "returns true when all checks pass" do
    expect(diagnostics.run).to be(true)

    output.rewind
    expect(output.string).to include("All checks passed.")
  end

  it "returns false when a check fails" do
    allow(context).to receive(:chat).and_raise(StandardError, "connection refused")

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
