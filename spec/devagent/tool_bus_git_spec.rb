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
        "command_allowlist" => ["git"]
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

  it "returns git status porcelain output" do
    Dir.chdir(repo) { `git init >/dev/null 2>&1` }
    File.write(File.join(repo, "a.txt"), "hi\n")

    status = tool_bus.git_status({})
    expect(status["exit_code"]).to eq(0)
    expect(status["stdout"]).to include("?? a.txt")
  end

  it "reports not a git repository when .git is missing" do
    status = tool_bus.git_status({})
    expect(status["exit_code"]).to eq(1)
    expect(status["stderr"]).to include("Not a git repository")
  end

  it "returns git diff output (unstaged)" do
    Dir.chdir(repo) { `git init >/dev/null 2>&1` }
    File.write(File.join(repo, "a.txt"), "hi\n")
    Dir.chdir(repo) { `git add a.txt >/dev/null 2>&1 && git commit -m init >/dev/null 2>&1` }
    File.write(File.join(repo, "a.txt"), "hi there\n")

    diff = tool_bus.git_diff("staged" => false)
    expect(diff["exit_code"]).to eq(0)
    expect(diff["stdout"]).to include("--- a/a.txt").and include("+++ b/a.txt")
  end
end

