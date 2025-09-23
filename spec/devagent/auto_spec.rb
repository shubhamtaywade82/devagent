# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Auto do
  let(:ctx) do
  instance_double(
    Devagent::PluginContext,
    repo_path: "/path/to/repo",
    config: { "auto" => { "allowlist" => ["**/*"] } },
    plugins: [],
    index: instance_double(Devagent::Index)
  )
end
  let(:auto) { described_class.new(ctx) }

  it "greets the user and exits when asked" do
    input = StringIO.new("exit\n")
    output = StringIO.new

    result = described_class.new(ctx, input: input, output: output).repl

    output.rewind
    expect(output.string).to include("Devagent ready").and include("Goodbye!")
    expect(result).to eq(:exited)
  end

  it "warns when a command is not recognised" do
    input = StringIO.new("plan feature\nexit\n")
    output = StringIO.new

    described_class.new(ctx, input: input, output: output).repl

    output.rewind
    expect(output.string).to include('Unrecognised command: "plan feature"')
  end
end