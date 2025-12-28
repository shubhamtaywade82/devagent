# frozen_string_literal: true

require "yaml"

module Devagent
  # Devagent::Config resolves global CLI configuration without depending on the current working directory.
  #
  # Precedence (highest -> lowest):
  # - CLI flags
  # - Environment variables
  # - User config file (~/.devagent.yml)
  # - Defaults
  module Config
    DEFAULT_OLLAMA_HOST = "http://localhost:11434"
    DEFAULT_OLLAMA_TIMEOUT_SECONDS = 300

    CONFIG_PATH = File.expand_path("~/.devagent.yml")

    module_function

    def user_config(path: CONFIG_PATH)
      return {} unless File.exist?(path)

      YAML.load_file(path) || {}
    rescue StandardError
      {}
    end

    # Returns [value, source_symbol]
    # source_symbol is one of: :cli, :env, :user_config, :default
    def resolve_ollama_host(cli_host: nil, env: ENV, config_path: CONFIG_PATH)
      host = cli_host.to_s.strip
      return [host, :cli] unless host.empty?

      env_host = env["OLLAMA_HOST"].to_s.strip
      return [env_host, :env] unless env_host.empty?

      cfg = user_config(path: config_path)
      file_host = dig_any(cfg, %w[ollama host]).to_s.strip
      return [file_host, :user_config] unless file_host.empty?

      [DEFAULT_OLLAMA_HOST, :default]
    end

    def resolve_ollama_timeout_seconds(env: ENV, config_path: CONFIG_PATH)
      cfg = user_config(path: config_path)
      raw = dig_any(cfg, %w[ollama timeout]).to_s.strip
      return [DEFAULT_OLLAMA_TIMEOUT_SECONDS, :default] if raw.empty?

      timeout = raw.to_i
      timeout = DEFAULT_OLLAMA_TIMEOUT_SECONDS if timeout <= 0
      [timeout, :user_config]
    end

    def format_source(source)
      case source
      when :cli
        "CLI flag (--ollama-host)"
      when :env
        "ENV[OLLAMA_HOST]"
      when :user_config
        CONFIG_PATH
      else
        "default"
      end
    end

    def dig_any(hash, path)
      return nil unless hash.is_a?(Hash)

      # Try string keys
      val = hash.dig(*path)
      return val unless val.nil?

      # Try symbol keys (best-effort)
      sym_path = path.map { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
      hash.dig(*sym_path)
    end
  end
end

