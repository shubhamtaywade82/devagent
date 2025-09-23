# frozen_string_literal: true

require "yaml"
require_relative "ollama"

module Devagent
  PluginContext = Struct.new(:repo_path, :config, :llm)

  # Minimal context: just config + LLM callable.
  module Context
    DEFAULTS = {
      "model" => "llama3.1:8b"
    }.freeze

    def self.build(repo_path)
      config = config_for(repo_path)
      llm = build_llm(config)
      PluginContext.new(repo_path, config, llm)
    end

    def self.config_for(repo_path)
      cfg_path = File.join(repo_path, ".devagent.yml")
      DEFAULTS.merge(File.exist?(cfg_path) ? YAML.load_file(cfg_path) : {})
    end
    private_class_method :config_for

    def self.build_llm(config)
      lambda do |prompt, **opts|
        Ollama.query(prompt, model: config.fetch("model"), **opts)
      end
    end
    private_class_method :build_llm
  end
end
