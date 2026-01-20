# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::Context do
  it "injects globally resolved ollama host/timeout into config" do
    repo = Dir.mktmpdir
    File.write(File.join(repo, "dummy.rb"), "puts 'hi'\n")

    allow(Devagent::Config).to receive_messages(resolve_ollama_host: ["http://example:11434", :env],
                                                resolve_ollama_timeout_seconds: [
                                                  12, :user_config
                                                ])

    ctx = described_class.build(repo, {})
    expect(ctx.config.dig("ollama", "host")).to eq("http://example:11434")
    expect(ctx.config.dig("ollama", "timeout")).to eq(12)
  ensure
    FileUtils.remove_entry(repo) if repo && Dir.exist?(repo)
  end
end
