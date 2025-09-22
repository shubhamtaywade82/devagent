# frozen_string_literal: true

require "json"
require "net/http"

module Devagent
  class Ollama
    ENDPOINT = URI("http://localhost:11434/api/generate")

    def self.query(prompt, model:)
      request = Net::HTTP::Post.new(ENDPOINT, "Content-Type" => "application/json")
      request.body = { model: model, prompt: prompt, stream: false }.to_json

      response = Net::HTTP.start(ENDPOINT.hostname, ENDPOINT.port) do |http|
        http.read_timeout = 120
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "Ollama request failed (#{response.code}): #{response.body}"
      end

      parsed = JSON.parse(response.body)
      parsed.fetch("response")
    rescue JSON::ParserError
      raise "Ollama returned invalid JSON"
    end
  end
end
