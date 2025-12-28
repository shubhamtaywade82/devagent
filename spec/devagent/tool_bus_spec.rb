# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::ToolBus do
  let(:repo) { Dir.mktmpdir }
  let(:config) do
    {
      "auto" => {
        "allowlist" => ["**/*"],
        "denylist" => [],
        "dry_run" => false,
        "command_allowlist" => ["bundle", "echo", "ruby"],
        "command_timeout_seconds" => 5,
        "command_max_output_bytes" => 10_000
      }
    }
  end
  let(:tracer) { instance_double(Devagent::Tracer, event: nil) }
  let(:context) do
    instance_double(
      Devagent::Context,
      repo_path: repo,
      config: config,
      tracer: tracer,
      plugins: []
    )
  end
  let(:registry) { Devagent::ToolRegistry.default }

  subject(:tool_bus) { described_class.new(context, registry: registry) }

  after do
    FileUtils.remove_entry(repo)
  end

  describe "#write_file" do
    it "writes content inside the repo and marks changes" do
      tool_bus.write_file("path" => "lib/example.rb", "content" => "class Example; end\n")

      expect(File.read(File.join(repo, "lib/example.rb"))).to include("Example")
      expect(tool_bus).to be_changes_made
    end

    it "respects dry run mode" do
      config["auto"]["dry_run"] = true

      tool_bus.write_file("path" => "lib/dry_run.rb", "content" => "puts 'hi'\n")

      expect(File.exist?(File.join(repo, "lib/dry_run.rb"))).to be(false)
      expect(tool_bus).not_to be_changes_made
    end

    it "raises when path is not allowed" do
      expect {
        tool_bus.write_file("path" => "../outside.txt", "content" => "nope")
      }.to raise_error(Devagent::Error)
    end
  end

  describe "#apply_patch" do
    let(:patch) do
      <<~PATCH
        --- a/file.txt
        +++ b/file.txt
        @@ -0,0 +1,2 @@
        +hello
        +world
      PATCH
    end

    it "skips when repository is not a git repo" do
      expect(tool_bus.apply_patch("patch" => patch)).to eq(:skipped)
      expect(tool_bus).not_to be_changes_made
    end

    it "applies patch when git repo is present" do
      Dir.chdir(repo) do
        `git init >/dev/null 2>&1`
      end
      File.write(File.join(repo, "file.txt"), "old\n")
      git_patch = <<~PATCH
        --- a/file.txt
        +++ b/file.txt
        @@ -1 +1,2 @@
        -old
        +hello
        +world
      PATCH

      result = tool_bus.apply_patch("patch" => git_patch)

      expect(result).to eq(git_patch)
      expect(File.read(File.join(repo, "file.txt"))).to include("hello")
      expect(tool_bus).to be_changes_made
    end
  end

  describe "#run_tests" do
    before do
      # Mock run_capture instead of run! since we changed the implementation
      allow(Devagent::Util).to receive(:run_capture).and_return({
        "stdout" => "80 examples, 0 failures\n",
        "stderr" => "",
        "exit_code" => 0,
        "success" => true
      })
    end

    it "executes provided command" do
      config["auto"]["command_allowlist"] = ["bundle"]
      expect(tool_bus.run_tests("command" => "bundle exec rspec")).to eq(:ok)
      expect(Devagent::Util).to have_received(:run_capture).with(["bundle", "exec", "rspec"], chdir: repo)
    end

    it "skips when dry run is enabled" do
      config["auto"]["dry_run"] = true

      expect(tool_bus.run_tests("command" => "bundle exec rspec")).to eq(:skipped)
      expect(Devagent::Util).not_to have_received(:run_capture)
    end
  end

  describe "#run_command" do
    before do
      allow(Devagent::Util).to receive(:run_capture).and_return(
        { "stdout" => "output\n", "stderr" => "", "exit_code" => 0, "success" => true }
      )
    end

    it "runs arbitrary commands inside the repo" do
      result = tool_bus.run_command("program" => "echo", "args" => ["hi"])

      expect(result).to include("stdout" => "output\n", "stderr" => "", "exit_code" => 0)
      expect(Devagent::Util).to have_received(:run_capture).with(["echo", "hi"], chdir: repo)
    end

    it "skips command execution in dry run" do
      config["auto"]["dry_run"] = true

      expect(tool_bus.run_command("program" => "echo", "args" => ["hi"])).to eq({ "stdout" => "", "stderr" => "", "exit_code" => 0 })
      expect(Devagent::Util).not_to have_received(:run_capture)
    end

    it "blocks dangerous commands" do
      expect {
        tool_bus.run_command("program" => "rm", "args" => ["-rf", "/"])
      }.to raise_error(Devagent::Error, /command not allowed/)
    end

    it "truncates excessive command output" do
      config["auto"]["command_max_output_bytes"] = 10
      allow(Devagent::Util).to receive(:run_capture).and_return(
        { "stdout" => "x" * 50, "stderr" => "", "exit_code" => 0, "success" => true }
      )

      result = tool_bus.run_command("program" => "echo", "args" => ["hi"])
      expect(result["stdout"]).to include("... (truncated to 10 bytes)")
    end

    it "returns a structured timeout result when the command times out" do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      result = tool_bus.run_command("program" => "echo", "args" => ["hi"])
      expect(result).to include("exit_code" => 124)
      expect(result["stderr"]).to include("timed out")
    end
  end

  describe "#delete_file" do
    it "deletes a file inside the repo and marks changes" do
      FileUtils.mkdir_p(File.join(repo, "lib"))
      File.write(File.join(repo, "lib/to_delete.rb"), "puts 'bye'\n")

      expect(tool_bus.delete_file("path" => "lib/to_delete.rb")).to eq({ "ok" => true })
      expect(File.exist?(File.join(repo, "lib/to_delete.rb"))).to be(false)
      expect(tool_bus).to be_changes_made
    end

    it "respects dry run mode" do
      config["auto"]["dry_run"] = true
      FileUtils.mkdir_p(File.join(repo, "lib"))
      File.write(File.join(repo, "lib/dry_delete.rb"), "puts 'bye'\n")

      expect(tool_bus.delete_file("path" => "lib/dry_delete.rb")).to eq({ "ok" => false })
      expect(File.exist?(File.join(repo, "lib/dry_delete.rb"))).to be(true)
      expect(tool_bus).not_to be_changes_made
    end
  end
end
