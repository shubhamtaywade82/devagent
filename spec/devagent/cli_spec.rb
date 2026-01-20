# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
RSpec.describe Devagent::CLI do
  let(:context) { instance_double(Devagent::Context) }

  before do
    allow(Devagent::Context).to receive(:build).and_return(context)
  end

  it "builds a context and starts the REPL (default)" do
    repl = instance_double(Devagent::Auto, repl: nil)

    allow(Devagent::Auto).to receive(:new).and_return(repl)

    described_class.start([])

    expect(Devagent::Context).to have_received(:build).with(Dir.pwd, {})
    expect(Devagent::Auto).to have_received(:new).with(context, input: $stdin, output: $stdout)
    expect(repl).to have_received(:repl)
  end

  it "runs diagnostics when the test command is invoked" do
    diagnostics = instance_double(Devagent::Diagnostics, run: true)

    allow(Devagent::Diagnostics).to receive(:new).and_return(diagnostics)

    expect { described_class.start(["test"]) }.not_to raise_error

    expect(Devagent::Context).to have_received(:build).with(Dir.pwd, {})
    expect(Devagent::Diagnostics).to have_received(:new).with(context, output: $stdout)
    expect(diagnostics).to have_received(:run)
  end

  it "exits when diagnostics fail" do
    diagnostics = instance_double(Devagent::Diagnostics, run: false)

    allow(Devagent::Diagnostics).to receive(:new).and_return(diagnostics)

    expect { described_class.start(["test"]) }.to raise_error(SystemExit) do |error|
      expect(error.status).to eq(1)
    end
  end

  it "prints diagnostic info" do
    allow(context).to receive(:model_for).with(:default).and_return("gpt-4o-mini")
    allow(context).to receive(:model_for).with(:planner).and_return("gpt-4o")
    allow(context).to receive(:model_for).with(:developer).and_return("gpt-4o-mini")
    allow(context).to receive(:model_for).with(:reviewer).and_return("gpt-4o")
    allow(context).to receive_messages(resolved_provider: "openai", embedding_backend_info: { "provider" => "openai",
                                                                                              "model" => "text-embedding-3-small" }, index: instance_double(Devagent::EmbeddingIndex, metadata: { "dim" => 1536 }), openai_available?: true, openai_uri_base: "https://api.openai.com/v1")

    expect { described_class.start(["diag"]) }.not_to raise_error
  end

  it "prints resolved configuration" do
    allow(Devagent::Config).to receive_messages(resolve_ollama_host: ["http://example:11434", :cli],
                                                resolve_ollama_timeout_seconds: [
                                                  60, :user_config
                                                ])

    expect { described_class.start(["config", "--ollama-host", "http://example:11434"]) }.not_to raise_error

    expect(Devagent::Config).to have_received(:resolve_ollama_host).with(cli_host: "http://example:11434")
    expect(Devagent::Config).to have_received(:resolve_ollama_timeout_seconds)
  end
end
# rubocop:enable Metrics/BlockLength
