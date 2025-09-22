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
end
