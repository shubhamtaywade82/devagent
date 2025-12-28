# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe Devagent::Auto do
  let(:repo_path) { Dir.mktmpdir }
  let(:tracer) { instance_double(Devagent::Tracer, event: nil) }
  let(:context) { instance_double(Devagent::PluginContext, repo_path: repo_path, tracer: tracer) }
  let(:orchestrator) { instance_double(Devagent::Orchestrator, run: nil) }

  before do
    allow(Devagent::Orchestrator).to receive(:new).and_return(orchestrator)
  end

  after do
    FileUtils.remove_entry(repo_path)
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
