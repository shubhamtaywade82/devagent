# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::Config do
  describe ".resolve_ollama_timeout_seconds" do
    it "returns timeout from user config when present" do
      Dir.mktmpdir do |dir|
        cfg_path = File.join(dir, "devagent.yml")
        File.write(cfg_path, <<~YAML)
          ollama:
            timeout: 42
        YAML

        timeout, source = described_class.resolve_ollama_timeout_seconds(env: {}, config_path: cfg_path)
        expect(timeout).to eq(42)
        expect(source).to eq(:user_config)
      end
    end

    it "falls back to default on invalid timeout" do
      Dir.mktmpdir do |dir|
        cfg_path = File.join(dir, "devagent.yml")
        File.write(cfg_path, <<~YAML)
          ollama:
            timeout: -5
        YAML

        timeout, _source = described_class.resolve_ollama_timeout_seconds(env: {}, config_path: cfg_path)
        expect(timeout).to eq(described_class::DEFAULT_OLLAMA_TIMEOUT_SECONDS)
      end
    end
  end

  describe ".format_source" do
    it "formats known sources" do
      expect(described_class.format_source(:cli)).to include("CLI")
      expect(described_class.format_source(:env)).to include("ENV")
      expect(described_class.format_source(:user_config)).to eq(described_class::CONFIG_PATH)
      expect(described_class.format_source(:default)).to eq("default")
    end
  end

  describe ".dig_any" do
    it "supports symbol keys" do
      cfg = { ollama: { host: "http://sym:11434" } }
      expect(described_class.dig_any(cfg, %w[ollama host])).to eq("http://sym:11434")
    end
  end

  describe ".user_config" do
    it "returns empty hash on invalid yaml" do
      Dir.mktmpdir do |dir|
        cfg_path = File.join(dir, "bad.yml")
        File.write(cfg_path, ":\n- totally not yaml\n")
        expect(described_class.user_config(path: cfg_path)).to eq({})
      end
    end
  end
end
