# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Devagent::Safety do
  let(:repo) { Dir.mktmpdir }
  let(:context) do
    instance_double(
      Devagent::Context,
      repo_path: repo,
      config: {
        "auto" => {
          "allowlist" => ["lib/**"],
          "denylist" => [".git/**", "config/credentials*"]
        }
      }
    )
  end
  let(:safety) { described_class.new(context) }

  after do
    FileUtils.remove_entry(repo)
  end

  it "allows paths inside the allowlist" do
    FileUtils.mkdir_p(File.join(repo, "lib"))
    expect(safety.allowed?("lib/example.rb")).to be(true)
  end

  it "denies paths on the denylist" do
    expect(safety.allowed?(".git/config")).to be(false)
  end

  it "denies attempts to access absolute paths" do
    expect(safety.allowed?("/etc/passwd")).to be(false)
  end

  it "denies attempts to escape the repo" do
    expect(safety.allowed?("../secrets.yml")).to be(false)
  end

  it "denies attempts to target system-managed directories" do
    FileUtils.mkdir_p(File.join(repo, "tmp/.rvm"))
    expect(safety.allowed?("tmp/.rvm/data")).to be(false)
  end
end
