# frozen_string_literal: true

require "openai"

module Devagent
  module LLM
    # Adapter that wraps the ruby-openai client and exposes a common interface
    # for querying, streaming, and embedding.
    class OpenAIAdapter
      DEFAULT_EMBED_MODEL = "text-embedding-3-small".freeze

      attr_reader :model, :provider

      def initialize(api_key:, model:, default_params: {}, embedding_model: nil)
        @client = OpenAI::Client.new(access_token: api_key)
        @model = model
        @default_params = symbolize_keys(default_params)
        @embedding_model = embedding_model || DEFAULT_EMBED_MODEL
        @provider = "openai"
      end

      def query(prompt, params: {}, response_format: nil)
        payload = build_parameters(prompt, params: params, response_format: response_format)
        response = client.chat(parameters: payload)
        fetch_content(response)
      rescue OpenAI::Error => e
        raise Error, "OpenAI (model=#{model}) query failed: #{e.message}"
      end

      def stream(prompt, params: {}, response_format: nil, on_token: nil)
        buffer = +""
        handler = proc do |chunk, _bytes|
          token = chunk.dig("choices", 0, "delta", "content")
          next if token.to_s.empty?

          on_token&.call(token)
          buffer << token
        end
        payload = build_parameters(prompt, params: params, response_format: response_format)
        payload[:stream] = handler
        client.chat(parameters: payload)
        buffer
      rescue OpenAI::Error => e
        raise Error, "OpenAI (model=#{model}) stream failed: #{e.message}"
      end

      def embed(texts, model: nil)
        response = client.embeddings(
          parameters: {
            model: model || embedding_model,
            input: Array(texts)
          }
        )
        response.fetch("data").map do |row|
          Array(row.fetch("embedding")).map(&:to_f)
        end
      rescue OpenAI::Error => e
        raise Error, "OpenAI embeddings (model=#{model || embedding_model}) failed: #{e.message}"
      end

      private

      attr_reader :client, :default_params, :embedding_model

      def build_parameters(prompt, params:, response_format:)
        merged = default_params.merge(symbolize_keys(params)).compact
        payload = {
          model: model,
          messages: [
            { role: "user", content: prompt }
          ],
          temperature: merged[:temperature],
          top_p: merged[:top_p]
        }.compact
        payload[:max_tokens] = merged[:max_tokens] if merged.key?(:max_tokens)
        payload[:response_format] = response_format if response_format
        payload
      end

      def fetch_content(response)
        response.dig("choices", 0, "message", "content").to_s
      end

      def symbolize_keys(hash)
        hash.to_h.each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
      end
    end
  end
end
