# frozen_string_literal: true

require "json"
require "net/http"

module Devagent
  # Ollama wraps local HTTP calls to the Ollama inference server.
  class Ollama
    ENDPOINT = URI("http://172.29.128.1:11434/api/generate")

    def self.query(prompt, model:)
      puts "[Ollama] Prompt: #{prompt[0..200]}..." # truncate for safety
      response = perform_request(prompt, model)
      pp response
      ensure_success!(response)
      parsed = parse_response(response.body)
      puts "[Ollama] Response: #{parsed[0..200]}..." # truncate
      parsed
    end

    def self.perform_request(prompt, model)
      request = Net::HTTP::Post.new(ENDPOINT, "Content-Type" => "application/json")
      request.body = { model: model, prompt: prompt, stream: false }.to_json

      Net::HTTP.start(ENDPOINT.hostname, ENDPOINT.port) do |http|
        http.read_timeout = 120
        http.request(request)
      end
    end
    private_class_method :perform_request

    def self.ensure_success!(response)
      return if response.is_a?(Net::HTTPSuccess)

      raise "Ollama request failed (#{response.code}): #{response.body}"
    end
    private_class_method :ensure_success!

    def self.parse_response(body)
      parsed = JSON.parse(body)
      parsed.fetch("response")
    rescue JSON::ParserError
      raise "Ollama returned invalid JSON"
    end
    private_class_method :parse_response
  end
end
