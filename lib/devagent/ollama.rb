# frozen_string_literal: true

require "json"
require "net/http"

module Devagent
  # Minimal Ollama wrapper
  class Ollama
    ENDPOINT = URI("#{ENV.fetch('OLLAMA_HOST', 'http://172.29.128.1:11434')}/api/generate")

    def self.query(prompt, model:)
      response = perform_request(prompt, model)
      ensure_success!(response)
      parse_response(response.body)
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
      body = response.body.to_s
      code = response.code.to_i
      if code == 404 && body.include?("model")
        raise "Ollama: the configured model was not found. Run `ollama list` and `ollama pull <model[:tag]>`, then set `model:` in .devagent.yml."
      end
      if code == 500 && body.include?("more system memory")
        raise "Ollama: the model needs more system memory than is available. Choose a smaller or quantized model and update `model` in .devagent.yml."
      end
      raise "Ollama request failed (#{response.code}): #{body}"
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
