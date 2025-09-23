# frozen_string_literal: true

require "tty-reader"

module Devagent
  # Minimal Q&A REPL: ask anything, prints LLM response.
  class Auto
    PROMPT = "devagent> "
    EXIT_COMMANDS = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout)
      @context = context
      @input = input
      @output = output
    end

    def repl
      greet
      reader = TTY::Reader.new
      loop do
        command = reader.read_line(PROMPT)
        break if command.nil? || exit_command?(command.strip)
        ask(command.strip)
      end
      farewell
    end

    private

    attr_reader :context, :input, :output

    def greet
      output.puts("Devagent Q&A REPL. Type 'exit' to quit.")
    end

    def farewell
      output.puts("Goodbye!")
      :exited
    end

    def exit_command?(command)
      EXIT_COMMANDS.include?(command.downcase)
    end

    def ask(text)
      begin
        answer = @context.llm.call(text)
        output.puts(answer.to_s)
      rescue => e
        output.puts("LLM error: #{e.message}")
        output.puts("Tip: set `model:` in .devagent.yml and ensure it's pulled with `ollama pull <model[:tag]>`.")
        output.puts("     If Ollama runs elsewhere, export OLLAMA_HOST, e.g. http://172.29.128.1:11434")
      end
    end
  end
end
