# frozen_string_literal: true

require_relative "llm/ollama_adapter"
require_relative "llm/openai_adapter"
require_relative "ollama"

module Devagent
  module LLM
    module_function

    ROLE_KEYS = {
      default: "model",
      planner: "planner_model",
      developer: "developer_model",
      reviewer: "reviewer_model",
      tester: "reviewer_model",
      embedding: "embed_model"
    }.freeze

    def for_role(context, role)
      context.llm_cache[role] ||= begin
        provider_name = provider_for(context, role)
        role_key = ROLE_KEYS.fetch(role, "model")
        adapter_for(context, role_key, provider_name)
      end
    end

    def provider(context)
      explicit = (context.config["provider"] || "auto").to_s.downcase
      return explicit if %w[openai ollama].include?(explicit)

      key_env = context.config.dig("openai", "api_key_env") || "OPENAI_API_KEY"
      ENV[key_env].to_s.empty? ? "ollama" : "openai"
    end

    def provider_for(context, role)
      return provider(context) unless context.respond_to?(:provider_for)

      context.provider_for(role)
    end

    def adapter_for(context, role_key, provider_name = nil)
      provider_name ||= provider(context)
      model = context.config[role_key] || context.config["model"]
      raise Devagent::Error, "No model configured for #{role_key}" unless model

      case provider_name
      when "openai"
        build_openai_adapter(context, model)
      when "ollama"
        build_ollama_adapter(context, model)
      else
        raise Devagent::Error, "Unknown provider: #{provider_name}"
      end
    end

    def build_openai_adapter(context, model)
      openai_config = context.config["openai"] || {}
      uri_base = openai_config["uri_base"] || "https://api.openai.com/v1"
      api_key = context.respond_to?(:openai_api_key) ? context.openai_api_key : nil
      key_env = openai_config["api_key_env"] || "OPENAI_API_KEY"
      raise Devagent::Error, "Set #{key_env} or configure openai.uri_base for Ollama" if api_key.to_s.empty?

      params = merged_generation_params(context, openai_config)
      options = symbolize_keys(openai_config["options"] || {})
      embedding_model = context.model_for(:embedding) if context.respond_to?(:model_for)

      LLM::OpenAIAdapter.new(
        api_key: api_key,
        model: model,
        uri_base: uri_base,
        request_timeout: openai_config["request_timeout"] || 600,
        params: params,
        options: options,
        embedding_model: embedding_model
      )
    end

    def build_ollama_adapter(context, model)
      params = context.llm_params("ollama") if context.respond_to?(:llm_params)
      params ||= context.config.dig("ollama", "params") || {}
      embedding_model = context.model_for(:embedding) if context.respond_to?(:model_for)

      LLM::OllamaAdapter.new(
        client: context.ollama_client,
        model: model,
        default_params: params,
        embedding_model: embedding_model
      )
    end

    def merged_generation_params(context, openai_config)
      params = {}
      params.merge!(context.config.dig("ollama", "params") || {})
      params.merge!(openai_config["params"] || {})
      symbolize_keys(params)
    end

    def symbolize_keys(hash)
      hash.to_h.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = value
      end
    end
  end
end
