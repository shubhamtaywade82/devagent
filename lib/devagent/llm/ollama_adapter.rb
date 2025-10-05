# frozen_string_literal: true

require_relative "../ollama"

module Devagent
  module LLM
    # Adapter that proxies generation, streaming, and embeddings to an Ollama client.
    class OllamaAdapter
      def initialize(client:, model:, params: {}, embedding_model: nil)
        @client = client
        @model = model
        @params = symbolize_keys(params)
        @embedding_model = embedding_model
      end

      def chat(prompt, model: @model, params: {})
        client.generate(prompt: prompt, model: model || @model, params: merged_params(params))
      end

      def stream(prompt, model: @model, params: {}, &block)
        buffer = +""
        client.stream(prompt: prompt, model: model || @model, params: merged_params(params)) do |token|
          next if token.nil?

          block&.call(token)
          buffer << token.to_s
        end
        buffer
      end

      def embed(texts, model: nil)
        Array(texts).map do |text|
          Array(client.embed(prompt: text, model: model || @embedding_model || @model)).map(&:to_f)
        end
      end

      private

      attr_reader :client, :params

      def merged_params(override)
        params.merge(symbolize_keys(override))
      end

      def symbolize_keys(hash)
        hash.to_h.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
      end
    end
  end
end
