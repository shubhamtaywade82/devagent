# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Auto do
  let(:context) { instance_double(Devagent::PluginContext) }

  it "greets the user and exits when asked" do
    input = StringIO.new("exit\n")
    output = StringIO.new

    result = described_class.new(context, input: input, output: output).repl

    output.rewind
    expect(output.string).to include("Devagent ready").and include("Goodbye!")
    expect(result).to eq(:exited)
  end

  it "warns when a command is not recognised" do
    input = StringIO.new("plan feature\nexit\n")
    output = StringIO.new

    described_class.new(context, input: input, output: output).repl

    output.rewind
    expect(output.string).to include('Unrecognised command: "plan feature"')
  end
end
