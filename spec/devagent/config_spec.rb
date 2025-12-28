# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::Config do
  describe ".resolve_ollama_host" do
    it "prefers CLI over ENV over user config over default" do
      Dir.mktmpdir do |dir|
        cfg_path = File.join(dir, "devagent.yml")
        File.write(cfg_path, <<~YAML)
          ollama:
            host: http://from-file:11434
        YAML

        env = { "OLLAMA_HOST" => "http://from-env:11434" }

        host, source = described_class.resolve_ollama_host(
          cli_host: "http://from-cli:11434",
          env: env,
          config_path: cfg_path
        )
        expect(host).to eq("http://from-cli:11434")
        expect(source).to eq(:cli)

        host, source = described_class.resolve_ollama_host(
          cli_host: nil,
          env: env,
          config_path: cfg_path
        )
        expect(host).to eq("http://from-env:11434")
        expect(source).to eq(:env)

        host, source = described_class.resolve_ollama_host(
          cli_host: nil,
          env: {},
          config_path: cfg_path
        )
        expect(host).to eq("http://from-file:11434")
        expect(source).to eq(:user_config)
      end
    end

    it "falls back to default when nothing is set" do
      host, source = described_class.resolve_ollama_host(cli_host: nil, env: {}, config_path: "/nope.yml")
      expect(host).to eq(described_class::DEFAULT_OLLAMA_HOST)
      expect(source).to eq(:default)
    end
  end
end

