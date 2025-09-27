# frozen_string_literal: true

require "yaml"
require_relative "plugin_loader"
require_relative "index"
require_relative "memory"
require_relative "ollama"
require_relative "util"
require_relative "repo_survey"

module Devagent
  PluginContext = Struct.new(:repo_path, :config, :llm, :shell, :index, :memory, :plugins, :survey)

  # Context builds the dependencies (LLM, shell, index, plugins) for the agent.
  module Context
    DEFAULTS = {
      "model" => "codellama",
      "auto" => {
        "max_iterations" => 3,
        "dry_run" => false,
        "require_tests_green" => true,
        "confirmation_threshold" => 0.7,
        "allowlist" => ["app/**", "lib/**", "spec/**", "config/**", "db/**", "src/**"],
        "denylist" => ["node_modules/**", "log/**", "tmp/**", ".git/**", "dist/**", "build/**"]
      },
      "index" => { "threads" => 8, "globs" => ["**/*.{rb,erb,haml,slim,js,jsx,ts,tsx,rb,ru}"] }
    }.freeze

    def self.build(repo_path)
      config = config_for(repo_path)
      llm = build_llm(config)
      shell = build_shell(repo_path)
      index = Index.new(repo_path, config["index"])
      memory = Memory.new(repo_path)
      base_ctx = PluginContext.new(repo_path, config, llm, shell, index, memory, [], nil)
      plugins = PluginLoader.load_plugins(base_ctx)
      survey = RepoSurvey.new(repo_path).capture!
      PluginContext.new(repo_path, config, llm, shell, index, memory, plugins, survey)
    end

    def self.config_for(repo_path)
      cfg_path = File.join(repo_path, ".devagent.yml")
      DEFAULTS.merge(File.exist?(cfg_path) ? YAML.load_file(cfg_path) : {})
    end
    private_class_method :config_for

    def self.build_llm(config)
      lambda do |prompt, **opts|
        Ollama.query(prompt, model: config["model"], **opts)
      end
    end
    private_class_method :build_llm

    def self.build_shell(repo_path)
      lambda do |cmd, chdir: repo_path|
        Util.run!(cmd, chdir: chdir)
      end
    end
    private_class_method :build_shell
  end
end
