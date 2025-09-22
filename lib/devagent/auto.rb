# frozen_string_literal: true

module Devagent
  class Auto
    PROMPT = "devagent> ".freeze
    EXIT_COMMANDS = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout)
      @context = context
      @input = input
      @output = output
    end

    def repl
      output.puts("Devagent ready. Type `exit` to quit.")

      loop do
        output.print(PROMPT)
        output.flush

        line = input.gets
        break if line.nil?

        command = line.strip
        next if command.empty?
        break if EXIT_COMMANDS.include?(command.downcase)

        output.puts("Unrecognised command: #{command.inspect}")
      end

      output.puts("Goodbye!")
      :exited
    end

    private

    attr_reader :context, :input, :output
  end
end
