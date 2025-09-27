# frozen_string_literal: true

require "stringio"
require "devagent/context"

RSpec.describe Devagent::Auto do
  let(:repo_path) { "/tmp/example" }
  let(:config) do
    {
      "auto" => {
        "allowlist" => ["**/*"],
        "max_iterations" => 2,
        "require_tests_green" => true,
        "confirmation_threshold" => 0.7
      }
    }
  end
  let(:llm) { instance_double(Proc) }
  let(:shell) { instance_double(Proc) }
  let(:index) { instance_double(Devagent::Index, build!: nil) }
  let(:memory) { instance_double(Devagent::Memory) }
  let(:survey) do
    instance_double(
      Devagent::RepoSurvey,
      structure_lines: ["lib/ (library runtime code)", "spec/ (RSpec tests)"],
      key_file_lines: ["Gemfile (Ruby dependencies)"],
      doc_previews: { "README.md" => "Welcome to Devagent" }
    )
  end
  let(:context) do
    Devagent::PluginContext.new(repo_path, config, llm, shell, index, memory, [], survey)
  end
  let(:reader) { instance_double(TTY::Reader) }
  let(:output) { StringIO.new }
  let(:spinner) { instance_double(TTY::Spinner, auto_spin: nil, stop: nil) }

  before do
    allow(TTY::Reader).to receive(:new).and_return(reader)
    allow(TTY::Spinner).to receive(:new).and_return(spinner)
  end

  describe "greeting" do
    it "prints repo summary and exits on exit command" do
      allow(reader).to receive(:read_line).and_return("exit", nil)

      result = described_class.new(context, input: StringIO.new, output: output).repl

      output.rewind
      text = output.string
      expect(text).to include("Devagent autonomous REPL")
      expect(text).to include("Structure: lib/ (library runtime code), spec/ (RSpec tests)")
      expect(text).to include("Key files: Gemfile (Ruby dependencies)")
      expect(text).to include("Docs: README.md")
      expect(result).to eq(:exited)
    end
  end

  describe "fallback mode" do
    it "delegates to the LLM when the planner returns no actions" do
      allow(reader).to receive(:read_line).and_return("What is this project?", "exit")
      allow(Devagent::Planner).to receive(:plan).and_return(Devagent::Plan.new([], 0.4))
      allow(llm).to receive(:call).and_return("A Ruby agent for local automation.")

      described_class.new(context, input: StringIO.new, output: output).repl

      output.rewind
      text = output.string
      expect(text).to include("No actions planned. Asking model directly...")
      expect(text).to include("A Ruby agent for local automation.")
    end
  end
end
