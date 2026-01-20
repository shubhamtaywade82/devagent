# frozen_string_literal: true

require_relative "../ollama"

module Devagent
  module LLM
    # Adapter that proxies to the Ollama HTTP API client.
    class OllamaAdapter
      attr_reader :model, :provider

      def initialize(client:, model:, default_params: {}, embedding_model: nil)
        @client = client
        @model = model
        @default_params = symbolize_keys(default_params)
        @embedding_model = embedding_model || model
        @provider = "ollama"
      end

      def query(prompt, params: {}, response_format: nil)
        ensure_no_response_format!(response_format)
        client.generate(
          prompt: prompt,
          model: model,
          params: merged_params(params)
        )
      rescue StandardError => e
        raise Error, "Ollama (model=#{model}) query failed: #{e.message}"
      end

      def stream(prompt, params: {}, response_format: nil, on_token: nil, &block)
        ensure_no_response_format!(response_format)
        buffer = +""
        handler = on_token || block
        client.stream(
          prompt: prompt,
          model: model,
          params: merged_params(params)
        ) do |token|
          next if token.nil?

          text = token.to_s
          handler&.call(text)
          buffer << text
        end
        buffer
      rescue StandardError => e
        raise Error, "Ollama (model=#{model}) stream failed: #{e.message}"
      end

      def embed(texts, model: nil)
        Array(texts).map do |text|
          Array(
            client.embed(
              prompt: text,
              model: model || embedding_model
            )
          ).map(&:to_f)
        end
      rescue StandardError => e
        raise Error, "Ollama embeddings (model=#{model || embedding_model}) failed: #{e.message}"
      end

      private

      attr_reader :client, :default_params, :embedding_model

      def merged_params(params)
        default_params.merge(symbolize_keys(params))
      end

      def ensure_no_response_format!(response_format)
        return unless response_format

        raise Error, "Ollama does not support response_format=#{response_format.inspect}"
      end

      def symbolize_keys(hash)
        hash.to_h.transform_keys(&:to_sym)
      end
    end
  end
end
