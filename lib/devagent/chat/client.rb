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

      attr_reader :model, :history, :system_prompt, :last_response_summary

      def initialize(model:, system_prompt: ENV.fetch("DEVAGENT_CHAT_SYSTEM_PROMPT", DEFAULT_SYSTEM_PROMPT), base_url: DEFAULT_URL, logger: nil)
        @model = model
        @system_prompt = system_prompt
        @base_url = base_url
        @history = []
        @json_buffer = String.new
        @assistant_response_content = String.new
        @logger = logger
        @on_response_start = nil
        @response_started = false
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

      def chat_stream(prompt, output: $stdout, color: :cyan, on_response_start: nil)
        append_user_message(prompt)
        reset_stream_state
        @on_response_start = on_response_start

        begin
          log_debug("chat.stream", endpoint: "/api/chat", model: @model)
          stream_chat_endpoint(output, color)
        rescue Faraday::ClientError => e
          raise unless legacy_chat_error?(e)

          log_warn("chat.stream.fallback", endpoint: "/api/chat", status: response_status(e), message: e.message)
          reset_stream_state
          stream_legacy_endpoint(output, color)
        end

        append_assistant_message
        @last_response_summary = summarized_response
        log_info("chat.response", text: @last_response_summary)
        output.puts
      rescue Faraday::Error => e
        output.puts Paint["Error communicating with Ollama: #{e.message}", :red]
      ensure
        @on_response_start = nil
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
        @response_started = false
        @last_response_summary = nil
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
        log_debug("chat.stream", endpoint: "/api/generate", model: @model)
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
        body = response&.body
        unless body
          response_started!
          return
        end

        body.split("\n").each do |raw_line|
          next if raw_line.strip.empty?

          line = normalize_line(raw_line)
          next if line.nil?

          data = safe_parse_json(line)
          next unless data

          response_started!

          content = data["response"]
          next unless content

          @assistant_response_content << content
          output.print(Paint[content, color])
          output.flush if output.respond_to?(:flush)
          log_info("chat.chunk", text: content)
        end

        response_started!
        nil
      end

      def safe_parse_json(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def normalize_line(line)
        stripped = line.sub(/\Adata:\s*/, "")
        stripped = stripped.sub(/\Aevent:\s*\w+\s*/, "")
        stripped = stripped.strip
        return nil if stripped.empty? || stripped == "[DONE]"

        stripped
      end

      def process_chunk(chunk, output, color)
        @json_buffer << chunk
        lines = @json_buffer.split("\n")
        @json_buffer = lines.pop || String.new

        lines.each do |raw_line|
          next if raw_line.strip.empty?

          line = normalize_line(raw_line)
          next if line.nil?

          begin
            data = JSON.parse(line)
          rescue JSON::ParserError
            @json_buffer.prepend("#{raw_line}\n")
            next
          end

          response_started!

          if data["error"]
            output.print(Paint["\nError: #{data["error"]}\n", :red])
            output.flush if output.respond_to?(:flush)
            next
          end

          content = extract_content(data)

          if content
            @assistant_response_content << content
            output.print(Paint[content, color])
            output.flush if output.respond_to?(:flush)
            log_info("chat.chunk", text: content)
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

      def response_started!
        return if @response_started

        @response_started = true
        @on_response_start&.call
      end

      def extract_content(data)
        if data["message"]
          interpret_message_content(data["message"]["content"])
        elsif data["response"]
          data["response"].to_s
        end
      end

      def interpret_message_content(content)
        case content
        when String
          content
        when Array
          content.map do |part|
            if part.is_a?(Hash)
              part["text"] || part["content"] || part.values_at("value", "data").compact.join
            else
              part.to_s
            end
          end.join
        when Hash
          content["text"] || content["content"] || content.values.compact.join
        end
      end

      def log_debug(event, payload = {})
        @logger&.debug(event, **payload)
      end

      def log_warn(event, payload = {})
        @logger&.warn(event, **payload)
      end

      def log_info(event, payload = {})
        @logger&.info(event, **payload)
      end

      def response_status(error)
        response = error.response
        return nil unless response

        response[:status] || response["status"]
      end

      def summarized_response
        summary = @assistant_response_content.strip
        summary.empty? ? "(no content)" : summary
      end
    end
  end
end
