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

  it "accepts add-file diffs with /dev/null header" do
    Dir.chdir(repo) { `git init >/dev/null 2>&1` }

    diff = <<~DIFF
      --- /dev/null
      +++ b/lib/new_file.rb
      @@ -0,0 +1,2 @@
      +puts "hi"
      +puts "bye"
    DIFF

    result = tool_bus.write_diff("path" => "lib/new_file.rb", "diff" => diff)
    expect(result).to eq({ "applied" => true })
    expect(File.read(File.join(repo, "lib/new_file.rb"))).to include("puts")
  end
end

