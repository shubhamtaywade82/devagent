# frozen_string_literal: true

require "paint"
require "faraday"
require "tty-spinner"
require "tty-table"

module Devagent
  module Chat
    # Session implements the interactive console loop for chatting with Ollama.
    class Session
      def initialize(model:, input: $stdin, output: $stdout, logger: nil, context: nil)
        @input = input
        @output = output
        @logger = logger
        @context = context
        @client = Client.new(model: model, logger: logger)
      end

      def start
        unless @client.server_available?
          @output.puts Paint["Unable to connect to Ollama server at #{Client::DEFAULT_URL}.", :red]
          @output.puts Paint["Please ensure the Ollama daemon is running (ollama serve).", :red]
          return false
        end

        @output.puts Paint["Connected. Type /exit or /quit to leave the console.", :green]
        repl_loop
        true
      rescue Faraday::Error => e
        @output.puts Paint["Connection error: #{e.message}", :red]
        false
      end

      private

      def repl_loop
        loop do
          prompt
          input = @input.gets
          break if input.nil?

          input = input.chomp
          next if input.strip.empty?

          break if %w[exit quit].include?(input.strip.downcase)

          if input.start_with?("/")
            handle_meta_command(input)
            next
          end

          @logger&.info("chat.prompt", text: input)
          stream_with_spinner(input)
        end

        @output.puts Paint["Goodbye!", :yellow]
      end

      def prompt
        @output.print(Paint[" > ", :green])
        @output.flush if @output.respond_to?(:flush)
      end

      def handle_meta_command(input)
        command, *args = input.strip.split

        case command
        when "/history"
          display_history
        when "/model"
          switch_model(args.first)
        else
          @output.puts Paint["Unknown command: #{command}", :red]
        end
      end

      def display_history
        @output.puts Paint["Conversation history:", :yellow]
        rows = @client.history.map do |message|
          [message[:role].capitalize, message[:content]]
        end
        table = TTY::Table.new(%w[Role Content], rows)
        @output.puts(table.render(:ascii, multiline: true, padding: [0, 1]))
      end

      def switch_model(new_model)
        if new_model.nil?
          @output.puts Paint["Usage: /model <model_name>", :yellow]
          return
        end

        @client.switch_model!(new_model)
        @output.puts Paint["Switched to model #{new_model}. Note: existing conversation history will still be sent to the new model.", :yellow]
      end

      def stream_with_spinner(input)
        context_snippets = gather_context(input)
        announce_context(context_snippets)

        spinner = TTY::Spinner.new("[:spinner] Thinking...", format: :dots, output: @output, clear: true)
        spinner_stopped = false
        stop_spinner = lambda do |message = nil, color = :yellow|
          next if spinner_stopped

          spinner.stop
          @output.puts(Paint[message, color]) if message && !message.empty?
          spinner_stopped = true
        rescue StandardError
          spinner_stopped = true
        end

        response_started = false
        spinner.auto_spin

        @client.chat_stream(
          input,
          output: @output,
          context_chunks: context_snippets,
          on_response_start: lambda do
            response_started = true
            stop_spinner.call
          end
        )
        summary = @client.last_response_summary || "(no content)"
        @logger&.success("chat.response", text: summary)
      rescue Faraday::Error => e
        stop_spinner.call("Error contacting Ollama", :red)
        @logger&.error("chat.stream", error: e.message)
      rescue StandardError => e
        stop_spinner.call("Unexpected error during chat", :red)
        @logger&.error("chat.stream", error: e.message)
        raise
      ensure
        stop_spinner.call("No response received", :yellow) unless response_started
      end

      def gather_context(user_input)
        return [] unless @context&.respond_to?(:index)

        index = @context.index
        return [] unless index.respond_to?(:retrieve)

        Array(index.retrieve(user_input, limit: 6)).map { |entry| entry.to_s.strip }.reject(&:empty?)
      rescue StandardError => e
        @logger&.warn("chat.context", error: e.message)
        []
      end

      def announce_context(snippets)
        return if snippets.empty?

        paths = context_paths(snippets)
        @logger&.info("chat.context", files: paths) if @logger
        @output.puts Paint["Context: #{paths.join(', ')}", :cyan]
      end

      def context_paths(snippets)
        snippets.map { |snippet| snippet.lines.first.to_s.strip }.reject(&:empty?).uniq
      end
    end
  end
end
