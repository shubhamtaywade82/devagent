# frozen_string_literal: true

require "openai"

module Devagent
  module LLM
    # Adapter for OpenAI's chat and embedding APIs via the ruby-openai client.
    class OpenAIAdapter
      def initialize(api_key:, model:, params: {}, embedding_model: nil)
        @client = OpenAI::Client.new(access_token: api_key)
        @model = model
        @params = symbolize_keys(params)
        @embedding_model = embedding_model || "text-embedding-3-small"
      end

      def chat(prompt, model: @model, params: {})
        response = client.chat(parameters: build_parameters(prompt, model || @model, params))
        response.dig("choices", 0, "message", "content").to_s
      end

      def stream(prompt, model: @model, params: {}, &block)
        buffer = +""
        stream_proc = lambda do |chunk, _bytes|
          token = chunk.dig("choices", 0, "delta", "content").to_s
          next if token.empty?

          block&.call(token)
          buffer << token
        end

        client.chat(parameters: build_parameters(prompt, model || @model, params, stream: stream_proc))
        buffer
      end

      def embed(texts, model: nil)
        payload = {
          model: model || embedding_model,
          input: Array(texts)
        }
        response = client.embeddings(parameters: payload)
        response.fetch("data").map { |item| Array(item.fetch("embedding")).map(&:to_f) }
      end

      private

      attr_reader :client, :params, :embedding_model

      def build_parameters(prompt, model, override_params, stream: nil)
        merged = params.merge(symbolize_keys(override_params)).compact
        base = {
          model: model,
          messages: [{ role: "user", content: prompt }],
          temperature: merged[:temperature],
          top_p: merged[:top_p]
        }.compact
        base[:max_tokens] = merged[:max_tokens] if merged.key?(:max_tokens)
        base[:stream] = stream if stream
        base
      end

      def symbolize_keys(hash)
        hash.to_h.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
      end
    end
  end
end
