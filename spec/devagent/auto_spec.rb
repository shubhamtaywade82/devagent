# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Auto do
  let(:context) { instance_double(Devagent::PluginContext) }
  let(:orchestrator) { instance_double(Devagent::Orchestrator, run: nil) }

  before do
    allow(Devagent::Orchestrator).to receive(:new).and_return(orchestrator)
  end

  it "greets the user and exits when asked" do
    input = StringIO.new("exit\n")
    output = StringIO.new

    result = described_class.new(context, input: input, output: output).repl

    output.rewind
    expect(output.string).to include("Devagent ready").and include("Goodbye!")
    expect(result).to eq(:exited)
  end

  it "forwards tasks to the orchestrator" do
    input = StringIO.new("add feature\nexit\n")
    output = StringIO.new

    described_class.new(context, input: input, output: output).repl

    expect(orchestrator).to have_received(:run).with("add feature")
  end
end
