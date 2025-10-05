# frozen_string_literal: true

module Devagent
  module LLM
    module_function

    def build(context, role: :default)
      provider = context.provider(role)
      model = model_for(context, role)
      params = context.llm_params(provider)
      embedding_model = embedding_model_for(context, role, provider)

      case provider
      when "openai"
        require_relative "llm/openai_adapter"
        api_key = context.openai_api_key
        raise "Set OPENAI_API_KEY or configure openai.api_key for OpenAI provider" if api_key.to_s.strip.empty?

        OpenAIAdapter.new(
          api_key: api_key,
          model: model,
          params: params,
          embedding_model: embedding_model
        )
      else
        require_relative "llm/ollama_adapter"
        OllamaAdapter.new(
          client: context.ollama,
          model: model,
          params: params,
          embedding_model: embedding_model
        )
      end
    end

    def model_for(context, role)
      case role
      when :planner
        context.planner_model
      when :embedding
        context.config.dig("index", "embed_model") || context.config["model"]
      else
        context.config["model"]
      end
    end

    def embedding_model_for(context, role, provider)
      if role == :embedding
        embed_model = context.config.dig("index", "embed_model")
        return embed_model unless embed_model.to_s.empty?

        return context.config.dig("openai", "embedding_model") if provider == "openai"
        return context.config["model"]
      end

      return context.config.dig("openai", "embedding_model") if provider == "openai"

      nil
    end
  end
end
