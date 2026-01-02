# frozen_string_literal: true

require "yaml"
require_relative "embedding_index"
require_relative "llm"
require_relative "config"
require_relative "memory"
require_relative "ollama"
require_relative "plugin_loader"
require_relative "session_memory"
require_relative "tool_registry"
require_relative "tool_bus"
require_relative "tracer"

module Devagent
  # Context assembles shared dependencies for a DevAgent run and resolves
  # provider/model selections for each role.
  class Context
    attr_reader :repo_path, :config, :memory, :session_memory, :tracer, :tool_registry, :tool_bus, :plugins, :index,
                :ollama_client, :llm_cache

    def self.build(repo_path, overrides = {})
      config = load_config(repo_path)
      merged = deep_merge(config, stringify_keys(overrides))

      # Resolve Ollama config without depending on repo/cwd.
      cli_host = overrides.dig("ollama", "host") || overrides.dig(:ollama, :host)
      host, _host_source = Devagent::Config.resolve_ollama_host(cli_host: cli_host)
      timeout, _timeout_source = Devagent::Config.resolve_ollama_timeout_seconds
      merged["ollama"] ||= {}
      merged["ollama"]["host"] = host
      merged["ollama"]["timeout"] = timeout

      new(repo_path, merged, overrides: overrides)
    end

    def self.load_config(repo_path)
      cfg_path = File.join(repo_path, ".devagent.yml")
      defaults.merge(File.exist?(cfg_path) ? YAML.load_file(cfg_path) || {} : {})
    end

    def self.defaults
      {
        "provider" => "auto",
        "model" => "gpt-4o-mini",
        "planner_model" => "gpt-4o-mini",
        "developer_model" => "gpt-4o-mini",
        "reviewer_model" => "gpt-4o",
        "embed_model" => "text-embedding-3-small",
        "ollama" => {
          "host" => "http://localhost:11434",
          "params" => {
            "temperature" => 0.2,
            "top_p" => 0.95
          }
        },
        "openai" => {
          "uri_base" => "https://api.openai.com/v1",
          "api_key_env" => "OPENAI_API_KEY",
          "request_timeout" => 600,
          "params" => {
            "temperature" => 0.2,
            "top_p" => 0.95
          },
          "options" => {
            "num_gpu" => 0,
            "num_ctx" => 2048
          }
        },
        "index" => {
          "globs" => ["**/*.{rb,ru,erb,haml,slim,js,jsx,ts,tsx}"],
          "chunk_size" => 1800,
          "overlap" => 200,
          "threads" => 8
        },
        "auto" => {
          "max_iterations" => 3,
          "require_tests_green" => true,
          "dry_run" => false,
          # Allowlist is by program name (first token), not a string prefix.
          "command_allowlist" => ["bundle", "ruby", "npm", "yarn", "rubocop", "rake", "make", "git"],
          "command_timeout_seconds" => 60,
          "command_max_output_bytes" => 20_000,
          "max_file_size_bytes" => 100_000, # Files larger than this will be read in chunks (100KB)
          "file_chunk_size" => 50_000, # Size of each chunk when reading large files (50KB)
          "enable_git_tools" => false,
          "allowlist" => ["app/**", "lib/**", "spec/**", "config/**", "db/**", "src/**"],
          "denylist" => [".git/**", "node_modules/**", "log/**", "tmp/**", "dist/**", "build/**", "coverage/**",
                         ".env*", "config/credentials*"]
        },
        "memory" => { "short_term_turns" => 20 },
        "ui" => { "quiet" => false }
      }
    end

    def self.stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end

    def self.deep_merge(base, overrides)
      result = base.dup
      overrides.each do |key, value|
        next if value.nil?

        result[key] = if value.is_a?(Hash) && base[key].is_a?(Hash)
                        deep_merge(base[key], stringify_keys(value))
                      else
                        value
                      end
      end
      result
    end

    def initialize(repo_path, config, overrides: {})
      @repo_path = repo_path
      @config = config
      @memory = Memory.new(repo_path)
      @session_memory = SessionMemory.new(repo_path, limit: config.dig("memory", "short_term_turns"))
      @tracer = Tracer.new(repo_path)
      @ollama_client = Ollama::Client.new(config.fetch("ollama", {}))
      @tool_registry = ToolRegistry.default
      @tool_bus = ToolBus.new(self, registry: @tool_registry)
      @plugins = PluginLoader.load_plugins(self)
      @plugins.each { |plugin| plugin.on_load(self) if plugin.respond_to?(:on_load) }
      @llm_cache = {}
      ensure_provider_requirements!
      @index = EmbeddingIndex.new(
        repo_path,
        config["index"],
        context: self,
        logger: tracer.method(:debug)
      )
    end

    def provider_for(role)
      raw = case role
            when :planner
              config["planner_provider"] || config["provider"]
            when :developer
              config["developer_provider"] || config["provider"]
            when :reviewer, :tester
              config["reviewer_provider"] || config["planner_provider"] || config["provider"]
            when :embedding
              config["embed_provider"] || config.dig("index", "embed_provider") || config["provider"]
            else
              config["provider"]
            end
      resolve_provider(raw)
    end

    def model_for(role)
      case role
      when :planner
        config["planner_model"] || config["model"]
      when :developer
        config["developer_model"] || config["model"]
      when :reviewer, :tester
        config["reviewer_model"] || config["planner_model"] || config["model"]
      when :embedding
        config["embed_model"] || config.dig("index", "embed_model") || default_embedding_model(provider_for(:embedding))
      else
        config["model"]
      end
    end

    def embedding_model_for(role, provider)
      return model_for(:embedding) if role == :embedding

      provider == "openai" ? config["embed_model"] : nil
    end

    def llm_params(provider)
      base = config.dig("ollama", "params") || {}
      overlay = provider == "openai" ? config.dig("openai", "params") || {} : {}
      symbolize_keys(base.merge(overlay))
    end

    def openai_api_key
      openai = config["openai"] || {}
      env_key = openai["api_key_env"] || "OPENAI_API_KEY"
      key = ENV[env_key]
      key = config.dig("openai", "api_key") if key.to_s.empty?
      key = "ollama" if key.to_s.empty? && !openai_uri_base.match?(/api\.openai\.com/i)
      key
    end

    def openai_available?
      !openai_api_key.to_s.strip.empty?
    end

    def openai_uri_base
      config.dig("openai", "uri_base") || "https://api.openai.com/v1"
    end

    def llm_for(role)
      LLM.for_role(self, role)
    end

    def query(role:, prompt:, stream: false, params: {}, response_format: nil, &on_token)
      adapter = llm_for(role)
      merged_params = llm_params(provider_for(role)).merge(symbolize_keys(params))
      if stream
        stream_with_interrupt(adapter, prompt, merged_params, response_format, &on_token)
      else
        adapter.query(prompt, params: merged_params, response_format: response_format)
      end
    end

    def resolved_provider
      provider_for(:default)
    end

    def embedding_backend_info
      {
        "provider" => provider_for(:embedding),
        "model" => model_for(:embedding)
      }
    end

    private

    def stream_with_interrupt(adapter, prompt, params, response_format, &on_token)
      adapter.stream(prompt, params: params, response_format: response_format, on_token: on_token)
    rescue Interrupt
      tracer.event("stream_interrupted")
      raise
    end

    def ensure_provider_requirements!
      providers = %i[default planner developer reviewer tester embedding].map { |role| provider_for(role) }.uniq
      return unless providers.include?("openai") && !openai_available?

      env_key = config.dig("openai", "api_key_env") || "OPENAI_API_KEY"
      raise Error, "OpenAI provider requested but credentials are missing (set #{env_key} or openai.api_key)"
    end

    def resolve_provider(raw)
      value = raw.to_s.strip
      case value
      when "openai"
        "openai"
      when "ollama"
        "ollama"
      else
        openai_available? ? "openai" : "ollama"
      end
    end

    def default_embedding_model(provider)
      provider == "openai" ? "text-embedding-3-small" : config.dig("index", "embed_model") || config["model"]
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
    end
  end

  PluginContext = Context
end
