# frozen_string_literal: true

require "yaml"
require_relative "plugin_loader"
require_relative "index"
require_relative "memory"
require_relative "ollama"
require_relative "util"

module Devagent
  PluginContext = Struct.new(:repo_path, :config, :llm, :shell, :index, :memory, :plugins)

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
      cfg_path = File.join(repo_path, ".devagent.yml")
      config = DEFAULTS.merge(File.exist?(cfg_path) ? YAML.load_file(cfg_path) : {})
      llm = lambda do |prompt, **opts|
        Ollama.query(prompt, model: config["model"], **opts)
      end
      shell = lambda do |cmd, chdir: repo_path|
        Util.run!(cmd, chdir: chdir)
      end
      index = Index.new(repo_path, config["index"])
      memory = Memory.new(repo_path)
      plugins = PluginLoader.load_plugins(
        PluginContext.new(repo_path, config, llm, shell, index, memory, [])
      )
      PluginContext.new(repo_path, config, llm, shell, index, memory, plugins)
    end
  end
end
