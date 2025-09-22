# frozen_string_literal: true

RSpec.describe Devagent::CLI do
  it "builds a context and starts the REPL" do
    ctx = instance_double(Devagent::PluginContext)
    repl = instance_double(Devagent::Auto, repl: nil)

    allow(Devagent::Context).to receive(:build).and_return(ctx)
    allow(Devagent::Auto).to receive(:new).and_return(repl)

    described_class.start(["start"])

    expect(Devagent::Context).to have_received(:build).with(Dir.pwd)
    expect(Devagent::Auto).to have_received(:new).with(ctx, input: $stdin, output: $stdout)
    expect(repl).to have_received(:repl)
  end

  it "runs diagnostics when the test command is invoked" do
    ctx = instance_double(Devagent::PluginContext)
    diagnostics = instance_double(Devagent::Diagnostics, run: true)

    allow(Devagent::Context).to receive(:build).and_return(ctx)
    allow(Devagent::Diagnostics).to receive(:new).and_return(diagnostics)

    expect { described_class.start(["test"]) }.not_to raise_error

    expect(Devagent::Context).to have_received(:build).with(Dir.pwd)
    expect(Devagent::Diagnostics).to have_received(:new).with(ctx, output: $stdout)
    expect(diagnostics).to have_received(:run)
  end

  it "exits when diagnostics fail" do
    ctx = instance_double(Devagent::PluginContext)
    diagnostics = instance_double(Devagent::Diagnostics, run: false)

    allow(Devagent::Context).to receive(:build).and_return(ctx)
    allow(Devagent::Diagnostics).to receive(:new).and_return(diagnostics)

    expect { described_class.start(["test"]) }.to raise_error(SystemExit) do |error|
      expect(error.status).to eq(1)
    end
  end
end
