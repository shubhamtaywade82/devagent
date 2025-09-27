# frozen_string_literal: true

require "paint"
require "faraday"

module Devagent
  module Chat
    # Session implements the interactive console loop for chatting with Ollama.
    class Session
      def initialize(model:, input: $stdin, output: $stdout)
        @input = input
        @output = output
        @client = Client.new(model: model)
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

          @client.chat_stream(input, output: @output)
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
        @client.history.each do |message|
          label = message[:role].capitalize.ljust(9)
          color = case message[:role]
                  when "user" then :green
                  when "assistant" then :cyan
                  else :yellow
                  end
          @output.puts Paint["#{label}: #{message[:content]}", color]
        end
      end

      def switch_model(new_model)
        if new_model.nil?
          @output.puts Paint["Usage: /model <model_name>", :yellow]
          return
        end

        @client.switch_model!(new_model)
        @output.puts Paint["Switched to model #{new_model}. Note: existing conversation history will still be sent to the new model.", :yellow]
      end
    end
  end
end
