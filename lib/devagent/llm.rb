# frozen_string_literal: true

require_relative "llm/ollama_adapter"
require_relative "llm/openai_adapter"

module Devagent
  module LLM
    module_function

    def for_role(context, role)
      context.llm_cache[role] ||= begin
        provider = context.provider_for(role)
        model = context.model_for(role)
        params = context.llm_params(provider)
        embedding_model = context.embedding_model_for(role, provider)
        build_adapter(context, provider: provider, model: model, params: params, embedding_model: embedding_model)
      end
    end

    def build_adapter(context, provider:, model:, params:, embedding_model: nil)
      case provider
      when "openai"
        api_key = context.openai_api_key
        raise Error, "OpenAI provider selected but OPENAI_API_KEY is not set" if api_key.to_s.empty?

        LLM::OpenAIAdapter.new(
          api_key: api_key,
          model: model,
          default_params: params,
          embedding_model: embedding_model
        )
      else
        LLM::OllamaAdapter.new(
          client: context.ollama_client,
          model: model,
          default_params: params,
          embedding_model: embedding_model
        )
      end
    end
  end
end
