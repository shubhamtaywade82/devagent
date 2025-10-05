# frozen_string_literal: true

require "yaml"
require_relative "embedding_index"
require_relative "llm"
require_relative "memory"
require_relative "ollama"
require_relative "plugin_loader"
require_relative "session_memory"
require_relative "tool_registry"
require_relative "tool_bus"
require_relative "tracer"

module Devagent
  # Context assembles shared dependencies for a DevAgent run.
  class Context
    attr_reader :repo_path, :config, :ollama, :memory, :session_memory,
                :index, :plugins, :tool_registry, :tool_bus, :tracer

    def self.build(repo_path)
      new(repo_path, load_config(repo_path))
    end

    def self.load_config(repo_path)
      cfg_path = File.join(repo_path, ".devagent.yml")
      defaults.merge(File.exist?(cfg_path) ? YAML.load_file(cfg_path) || {} : {})
    end

    def self.defaults
      {
        "model" => "qwen2.5-coder:7b-instruct",
        "planner_model" => "llama3.1:8b-instruct",
        "provider" => "ollama",
        "ollama" => {
          "host" => "http://localhost:11434",
          "params" => {
            "temperature" => 0.2,
            "top_p" => 0.95
          }
        },
        "openai" => {
          "params" => {
            "temperature" => 0.2,
            "top_p" => 0.95
          },
          "embedding_model" => "text-embedding-3-small"
        },
        "index" => {
          "embed_model" => "nomic-embed-text",
          "embed_provider" => "ollama",
          "globs" => ["**/*.{rb,ru,erb,haml,slim,js,jsx,ts,tsx}"],
          "chunk_size" => 1800,
          "overlap" => 200,
          "threads" => 8
        },
        "auto" => {
          "max_iterations" => 3,
          "require_tests_green" => true,
          "dry_run" => false,
          "allowlist" => ["app/**", "lib/**", "spec/**", "config/**", "db/**", "src/**"],
          "denylist" => [".git/**", "node_modules/**", "log/**", "tmp/**", "dist/**", "build/**", ".env*", "config/credentials*"]
        },
        "memory" => { "short_term_turns" => 20 }
      }
    end

    def initialize(repo_path, config)
      @repo_path = repo_path
      @config = config
      @memory = Memory.new(repo_path)
      @session_memory = SessionMemory.new(repo_path, limit: config.dig("memory", "short_term_turns"))
      @tracer = Tracer.new(repo_path)
      @ollama = Ollama::Client.new(config.fetch("ollama", {}))
      @tool_registry = ToolRegistry.default
      @tool_bus = ToolBus.new(self, registry: @tool_registry)
      @index = EmbeddingIndex.new(repo_path, config["index"], embedder: method(:embed_text), logger: @tracer.method(:debug))
      @plugins = PluginLoader.load_plugins(self)
      @plugins.each { |plugin| plugin.on_load(self) if plugin.respond_to?(:on_load) }
      @llms = {}
    end

    def planner_model
      config["planner_model"] || config["model"]
    end

    def provider(role = :default)
      case role
      when :planner
        config["planner_provider"] || provider(:default)
      when :embedding
        config.dig("index", "embed_provider") || provider(:default)
      else
        config["provider"] || "ollama"
      end
    end

    def providers
      %i[default planner embedding].map { |role| provider(role) }.compact.uniq
    end

    def llm_params(provider)
      params =
        case provider
        when "openai"
          config.dig("openai", "params")
        else
          config.dig("ollama", "params")
        end
      symbolize_keys(params || {})
    end

    def openai_api_key
      key = config.dig("openai", "api_key") || ENV["OPENAI_API_KEY"]
      key&.strip
    end

    def llm(role = :default)
      @llms[role] ||= Devagent::LLM.build(self, role: role)
    end

    def embed_text(text, model: config.dig("index", "embed_model"))
      embeddings = llm(:embedding).embed([text], model: model)
      Array(embeddings.first).map(&:to_f)
    end

    def chat(prompt, model: config["model"], stream: false, params: {}, &block)
      adapter = llm(:default)
      merged_params = llm_params(provider(:default)).merge(symbolize_keys(params))
      if stream
        adapter.stream(prompt, model: model, params: merged_params) do |token|
          block&.call(token)
        end
      else
        adapter.chat(prompt, model: model, params: merged_params)
      end
    end

    def planner(prompt)
      adapter = llm(:planner)
      params = llm_params(provider(:planner)).merge(temperature: 0.1)
      adapter.chat(prompt, model: planner_model, params: params)
    end

    private

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
    end
  end

  PluginContext = Context
end
