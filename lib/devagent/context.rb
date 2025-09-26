# frozen_string_literal: true

require "yaml"
require_relative "ollama"

module Devagent
  PluginContext = Struct.new(:repo_path, :config, :llm)

  module Context
    DEFAULTS = {
      "model" => "deepseek-coder:6.7b",
      "auto"  => {
        "allowlist" => ["**/*"],
        "denylist"  => ["node_modules/**", ".git/**", "tmp/**", "log/**"]
      }
    }.freeze

    def self.build(repo_path)
      config = config_for(repo_path)
      llm = build_llm(config)
      PluginContext.new(repo_path, config, llm)
    end

    def self.config_for(repo_path)
      cfg = File.join(repo_path, ".devagent.yml")
      DEFAULTS.merge(File.exist?(cfg) ? YAML.load_file(cfg) : {})
    end
    private_class_method :config_for

    def self.build_llm(config)
      lambda { |prompt, **opts| Ollama.query(prompt, model: config.fetch("model"), **opts) }
    end
    private_class_method :build_llm
  end
end
