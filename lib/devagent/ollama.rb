# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Devagent
  module Ollama
    # Client wraps HTTP calls to the Ollama server for generation, streaming, and embeddings.
    class Client
      DEFAULT_HOST = "http://localhost:11434"
      DEFAULT_TIMEOUT_SECONDS = 300

      def initialize(config = {})
        host = config.fetch("host", DEFAULT_HOST)
        @base_uri = URI(host)
        @default_params = config.fetch("params", {})
        @read_timeout = config.fetch("timeout", DEFAULT_TIMEOUT_SECONDS).to_i
      end

      def generate(prompt:, model:, params: {})
        body = request_json("/api/generate", prompt: prompt, model: model, stream: false, options: params)
        body.fetch("response")
      end

      def stream(prompt:, model:, params: {}, &)
        request_stream("/api/generate", prompt: prompt, model: model, stream: true, options: params, &)
      end

      def embed(prompt:, model:)
        response = request_json("/api/embeddings", prompt: prompt, model: model)
        Array(response["embedding"] || response["embeddings"])
      end

      private

      attr_reader :base_uri, :default_params

      def request_json(path, payload)
        response = http_post(path, payload)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON from Ollama: #{e.message}"
      end

      def request_stream(path, payload)
        http = build_http
        request = build_request(path, payload)
        http.request(request) do |response|
          raise Error, "Ollama #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            chunk.to_s.each_line do |line|
              next if line.strip.empty?

              data = JSON.parse(line)
              token = data["response"]
              yield token if token && block_given?
            end
          end
        end
      end

      def http_post(path, payload)
        http = build_http
        request = build_request(path, payload)
        response = http.request(request)
        raise Error, "Ollama #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        response
      end

      def build_http
        Net::HTTP.new(base_uri.host, base_uri.port).tap do |http|
          http.read_timeout = @read_timeout
        end
      end

      def build_request(path, payload)
        request = Net::HTTP::Post.new(path)
        request["Content-Type"] = "application/json"
        merged = default_params.merge(payload.delete(:options) || {})
        body = payload.dup
        body[:options] = merged unless merged.empty?
        request.body = body.to_json
        request
      end
    end
  end
end
