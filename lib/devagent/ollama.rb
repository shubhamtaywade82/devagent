# frozen_string_literal: true

require "json"
require "net/http"

module Devagent
  # Ollama wraps local HTTP calls to the Ollama inference server.
  class Ollama
    ENDPOINT = URI("http://172.29.128.1:11434/api/generate")

    class << self
      def query(prompt, model:)
        log_debug("Prompt", prompt)
        response = perform_request(prompt, model)
        log_debug("HTTP Response", response.body)
        ensure_success!(response)
        parsed = parse_response(response.body)
        log_debug("Parsed Response", parsed)
        parsed
      end

      private

      def perform_request(prompt, model)
        request = Net::HTTP::Post.new(ENDPOINT, "Content-Type" => "application/json")
        request.body = { model: model, prompt: prompt, stream: false }.to_json

        Net::HTTP.start(ENDPOINT.hostname, ENDPOINT.port) do |http|
          http.read_timeout = 120
          http.request(request)
        end
      end

      def ensure_success!(response)
        return if response.is_a?(Net::HTTPSuccess)

        raise "Ollama request failed (#{response.code}): #{response.body}"
      end

      def parse_response(body)
        parsed = JSON.parse(body)
        parsed.fetch("response")
      rescue JSON::ParserError
        raise "Ollama returned invalid JSON"
      end

      def log_debug(label, data)
        return unless debug_mode?

        text = data.to_s
        snippet = text.length > 200 ? "#{text[0, 200]}…" : text
        $stderr.puts("[Ollama] #{label}: #{snippet}")
      rescue StandardError
        nil
      end

      def debug_mode?
        ENV.fetch("DEVAGENT_DEBUG_LLM", nil)&.match?(/^(1|true|yes)$/i)
      end
    end
  end
end
