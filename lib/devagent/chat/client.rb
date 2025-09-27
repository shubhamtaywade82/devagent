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

      def chat_stream(prompt, output: $stdout, color: :cyan, on_response_start: nil, context_chunks: [])
        append_user_message(prompt, context_chunks)
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

      def append_user_message(prompt, context_chunks)
        @history << { role: "user", content: build_user_message(prompt, context_chunks) }
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
        response = @conn.post("/api/chat") do |req|
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

        finalize_stream(output, color)
        handle_chat_completion(response, output, color) if @assistant_response_content.empty?
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

        finalize_stream(output, color)
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
        process_response_body(response&.body, output, color)
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
        stripped = stripped.chomp(',')
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

          handle_parsed_chunk(data, raw_line, output, color)
        end
      end

      def handle_chat_completion(response, output, color)
        process_response_body(response&.body, output, color)
      end

      def process_response_body(body, output, color)
        return if body.nil? || body.empty?

        log_debug("chat.response.body", body: body)

        split_payload(body).each do |raw_line|
          next if raw_line.strip.empty?

          line = normalize_line(raw_line)
          next if line.nil?

          data = safe_parse_json(line)
          next unless data

          handle_parsed_chunk(data, raw_line, output, color)
        end
      end

      def handle_parsed_chunk(data, raw_line, output, color)
        return unless data

        response_started!
        log_debug("chat.chunk.raw", raw: raw_line, parsed: data)

        if data["error"]
          output.print(Paint["\nError: #{data["error"]}\n", :red])
          output.flush if output.respond_to?(:flush)
          return
        end

        content = extract_content(data)

        if content && !content.empty?
          @assistant_response_content << content
          output.print(Paint[content, color])
          output.flush if output.respond_to?(:flush)
          log_info("chat.chunk", text: content)
        end

        handle_done_reason(data, output)
      end

      def handle_done_reason(data, output)
        return unless data["done"]

        done_reason = data["done_reason"]
        return if done_reason.nil? || done_reason == "stop"

        chunk_message = data["message"]
        content = extract_message_content(chunk_message)
        if content && !content.empty?
          @assistant_response_content << content
          output.print(Paint[content, color])
          output.flush if output.respond_to?(:flush)
          log_info("chat.chunk", text: content)
        end

        output.print(Paint["\n(#{done_reason})", :yellow])
        output.flush if output.respond_to?(:flush)
      end

      def finalize_stream(output, color)
        return if @json_buffer.nil? || @json_buffer.strip.empty?

        buffer = @json_buffer.dup
        @json_buffer = String.new
        process_response_body(buffer, output, color)
      end

      def split_payload(payload)
        normalized = payload.gsub(/}\s*{/, "}\n{")
        normalized.split("\n")
      end

      def response_started!
        return if @response_started

        @response_started = true
        @on_response_start&.call
      end

      def extract_content(data)
        return unless data.is_a?(Hash)

        if data.key?("message")
          extract_message_content(data["message"])
        elsif data.key?("delta")
          extract_message_content(data["delta"])
        elsif data.key?("response")
          data["response"].to_s
        elsif data.key?("content")
          interpret_message_content(data["content"])
        elsif data.key?("text")
          data["text"].to_s
        end
      end

      def extract_message_content(message)
        return if message.nil?

        if message.is_a?(Hash)
          if message.key?("content")
            interpret_message_content(message["content"])
          elsif message.key?("delta")
            extract_message_content(message["delta"])
          elsif message.key?("text")
            message["text"].to_s
          elsif message.key?("message")
            extract_message_content(message["message"])
          end
        elsif message.is_a?(Array)
          interpret_message_content(message)
        else
          message.to_s
        end
      end

      def interpret_message_content(content)
        return if content.nil?

        case content
        when String
          content
        when Array
          content.map do |part|
            if part.is_a?(Hash)
              part["text"] || part["content"] || part.values_at("value", "data", "delta").compact.join
            else
              part.to_s
            end
          end.join
        when Hash
          content["text"] || content["content"] || content["value"] || content["data"] ||
            content.values.select { |value| value.is_a?(String) }.join
        end
      end

      def build_user_message(prompt, context_chunks)
        return prompt if context_chunks.nil? || context_chunks.empty?

        <<~MSG.strip
          Repository context:
          #{format_context_chunks(context_chunks)}

          User request:
          #{prompt}
        MSG
      end

      def format_context_chunks(chunks)
        chunks.map do |chunk|
          chunk = chunk.strip
          next if chunk.empty?

          path, body = chunk.split("\n", 2)
          body = body.to_s

          formatted_body = body.strip.empty? ? "(file empty or binary)" : body

          <<~SECTION.strip
            File: #{path}
            ```
            #{formatted_body}
            ```
          SECTION
        end.compact.join("\n\n")
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
