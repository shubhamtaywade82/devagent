# frozen_string_literal: true

require "json"
require "faraday"
require "paint"

module Devagent
  module Chat
    # Client encapsulates streaming chat interactions with the local Ollama server.
    class Client
      DEFAULT_URL = "http://172.29.128.1:11434"
      DEFAULT_SYSTEM_PROMPT = "You are a concise, helpful assistant designed for a terminal environment."

      attr_reader :model, :history, :system_prompt

      def initialize(model:, system_prompt: ENV.fetch("DEVAGENT_CHAT_SYSTEM_PROMPT", DEFAULT_SYSTEM_PROMPT), base_url: DEFAULT_URL)
        @model = model
        @system_prompt = system_prompt
        @base_url = base_url
        @history = []
        @json_buffer = String.new
        @assistant_response_content = String.new
        @conn = build_connection
        seed_system_prompt
      end

      def server_available?
        @conn.get("/api/version")
        true
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError
        false
      end

      def ensure_server_available!
        return if server_available?

        raise Faraday::ConnectionFailed, "Unable to connect to Ollama server at #{@base_url}"
      end

      def chat_stream(prompt, output: $stdout, color: :cyan)
        append_user_message(prompt)
        reset_stream_state

        begin
          stream_chat_endpoint(output, color)
        rescue Faraday::ClientError => e
          raise unless legacy_chat_error?(e)

          reset_stream_state
          stream_legacy_endpoint(output, color)
        end

        append_assistant_message
        output.puts
      rescue Faraday::Error => e
        output.puts Paint["Error communicating with Ollama: #{e.message}", :red]
      end

      def switch_model!(new_model)
        return if new_model.nil? || new_model.strip.empty?

        @model = new_model
      end

      private

      def build_connection
        Faraday.new(url: @base_url, request: { open_timeout: 5, timeout: 30 }) do |faraday|
          faraday.response :raise_error
          faraday.adapter Faraday.default_adapter
        end
      end

      def seed_system_prompt
        return if @system_prompt.nil? || @system_prompt.strip.empty?

        @history << { role: "system", content: @system_prompt }
      end

      def append_user_message(prompt)
        @history << { role: "user", content: prompt }
      end

      def append_assistant_message
        @history << { role: "assistant", content: @assistant_response_content.dup }
      end

      def build_messages
        @history
      end

      def reset_stream_state
        @json_buffer = String.new
        @assistant_response_content = String.new
      end

      def stream_chat_endpoint(output, color)
        @conn.post("/api/chat") do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate(
            model: @model,
            messages: build_messages,
            stream: true
          )
          req.options.on_data = proc do |chunk, _size|
            process_chunk(chunk, output, color)
          end
        end
      end

      def stream_legacy_endpoint(output, color)
        response = @conn.post("/api/generate") do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate(
            model: @model,
            prompt: build_legacy_prompt,
            stream: true
          )
          req.options.on_data = proc do |chunk, _size|
            process_chunk(chunk, output, color)
          end
        end

        handle_legacy_completion(response, output, color)
      end

      def legacy_chat_error?(error)
        response = error.response
        return false unless response

        status = response[:status] || response["status"]
        [404, 405].include?(status.to_i)
      end

      def build_legacy_prompt
        segments = @history.map do |message|
          role = case message[:role]
                 when "system" then "System"
                 when "user" then "User"
                 when "assistant" then "Assistant"
                 else message[:role].to_s.capitalize
                 end

          content = message[:content].to_s
          content.empty? ? role : "#{role}: #{content}"
        end

        segments << "Assistant:"
        segments.join("\n\n")
      end

      def handle_legacy_completion(response, output, color)
        return unless response&.body

        response.body.split("\n").each do |line|
          next if line.strip.empty?

          data = safe_parse_json(line)
          next unless data

          content = data["response"]
          next unless content

          @assistant_response_content << content
          output.print(Paint[content, color])
          output.flush if output.respond_to?(:flush)
        end

        nil
      end

      def safe_parse_json(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def process_chunk(chunk, output, color)
        @json_buffer << chunk
        lines = @json_buffer.split("\n")
        @json_buffer = lines.pop || String.new

        lines.each do |line|
          next if line.strip.empty?

          begin
            data = JSON.parse(line)
          rescue JSON::ParserError
            @json_buffer.prepend(line)
            next
          end

          if data["error"]
            output.print(Paint["\nError: #{data["error"]}\n", :red])
            output.flush if output.respond_to?(:flush)
            next
          end

          content = if data["message"] && data["message"]["content"]
                      data["message"]["content"]
                    elsif data["response"]
                      data["response"]
                    end

          if content
            @assistant_response_content << content
            output.print(Paint[content, color])
            output.flush if output.respond_to?(:flush)
          end

          next unless data["done"]

          if data["done_reason"] == "stop"
            # normal completion
          elsif data["done_reason"]
            output.print(Paint["\n(#{data["done_reason"]})", :yellow])
            output.flush if output.respond_to?(:flush)
          end
        end
      end
    end
  end
end
