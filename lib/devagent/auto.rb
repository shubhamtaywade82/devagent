# frozen_string_literal: true

module Devagent
  # Auto exposes the interactive REPL that drives autonomous workflows.
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

      while (command = read_command)
        next if command.empty?
        break if exit_command?(command)

        output.puts("Unrecognised command: #{command.inspect}")
      end

      farewell
    end

    private

    attr_reader :context, :input, :output

    def greet
      output.puts("Devagent ready. Type `exit` to quit.")
    end

    def farewell
      output.puts("Goodbye!")
      :exited
    end

    def read_command
      output.print(PROMPT)
      output.flush
      input.gets&.strip
    end

    def exit_command?(command)
      EXIT_COMMANDS.include?(command.downcase)
    end
  end
end
