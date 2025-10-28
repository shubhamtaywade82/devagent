# frozen_string_literal: true

require "openai"
require "json"

module Devagent
  module LLM
    # Adapter for the OpenAI-compatible chat API. Works with api.openai.com and
    # Ollama's /v1 endpoint by routing custom options through extra_body.
    class OpenAIAdapter
      DEFAULT_EMBED_MODEL = "text-embedding-3-small"

      attr_reader :model, :provider

      def initialize(api_key:, model:, uri_base:, request_timeout: 600, params: {}, options: {}, embedding_model: nil)
        @model = model
        @gen_params = symbolize_keys(params || {})
        @ollama_options = symbolize_keys(options || {})
        @embedding_model = embedding_model || DEFAULT_EMBED_MODEL
        @provider = "openai"
        @request_timeout = request_timeout

        @client = OpenAI::Client.new(
          access_token: api_key,
          uri_base: uri_base,
          request_timeout: request_timeout
        )
        @is_ollama_compat = uri_base !~ /api\.openai\.com/i
      end

      def query(prompt, params: {}, response_format: nil)
        payload = build_payload(prompt, params: params, response_format: response_format)
        call_with_retry(payload) do |request_params|
          response = client.chat(parameters: request_params)
          response.dig("choices", 0, "message", "content").to_s
        end
      end

      def stream(prompt, params: {}, response_format: nil, on_token: nil, &block)
        buffer = +""
        handler = on_token || block
        payload = build_payload(prompt, params: params, response_format: response_format)
        payload[:stream] = proc do |chunk, _bytes|
          delta = chunk.dig("choices", 0, "delta", "content")
          next if delta.to_s.empty?

          handler&.call(delta)
          buffer << delta
        end

        call_with_retry(payload) do |request_params|
          client.chat(parameters: request_params)
          buffer
        end
      end

      def embed(texts, model: nil)
        payload = { model: model || embedding_model, input: Array(texts) }
        response = client.embeddings(parameters: payload)
        response.fetch("data").map { |row| Array(row.fetch("embedding")).map(&:to_f) }
      end

      private

      attr_reader :client, :gen_params, :ollama_options, :embedding_model, :request_timeout

      def build_payload(prompt, params:, response_format:)
        merged = gen_params.merge(symbolize_keys(params || {}))
        base = {
          model: model,
          messages: [{ role: "user", content: prompt }],
          temperature: merged[:temperature],
          top_p: merged[:top_p]
        }.compact
        base[:max_tokens] = merged[:max_tokens] if merged.key?(:max_tokens)
        base[:response_format] = response_format if response_format
        attach_extra_body(base)
      end

      def attach_extra_body(base)
        return base unless @is_ollama_compat
        return base if ollama_options.empty?

        base.merge(extra_body: { options: ollama_options })
      end

      def call_with_retry(base_payload)
        yield(base_payload)
      rescue StandardError => error
        raise error unless retry_without_extra_body?(base_payload, error)

        stripped = base_payload.dup
        stripped.delete(:extra_body)
        begin
          yield(stripped)
        rescue StandardError
          raise error
        end
      end

      def retry_without_extra_body?(payload, error)
        return false unless payload[:extra_body]

        status = if error.respond_to?(:status_code)
                   error.status_code
                 elsif error.respond_to?(:response)
                   error.response[:status] rescue nil
                 end
        status = status.to_i
        return true if status >= 500 && status < 600

        message = error.message.to_s
        message.include?("500") || message.include?("Internal Server Error")
      end

      def symbolize_keys(hash)
        hash.to_h.each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
      end
    end
  end
end
