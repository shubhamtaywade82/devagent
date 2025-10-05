# frozen_string_literal: true

require "tty-reader"
require_relative "orchestrator"

module Devagent
  # Auto provides a simple REPL shell for the autonomous agent.
  class Auto
    PROMPT = "devagent> "
    EXIT = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout)
      @context = context
      @input = input
      @output = output
      @reader = TTY::Reader.new(input: input, output: output)
      @orchestrator = Orchestrator.new(context, output: output)
    end

    def repl
      output.puts("Devagent ready. Type 'exit' to quit.")
      loop do
        line = reader.read_line(PROMPT)
        break if line.nil? || EXIT.include?(line.strip.downcase)
        next if line.strip.empty?

        if line.strip.downcase == "start"
          output.puts("Already running the REPL.")
          next
        end

        begin
          orchestrator.run(line.strip)
        rescue StandardError => e
          output.puts("Error: #{e.message}")
          context.tracer.event("repl_error", message: e.message)
        end
      rescue Interrupt
        output.puts("^C")
      end

      output.puts("Goodbye!")
      :exited
    end

    private

    attr_reader :context, :reader, :output, :orchestrator
  end
end
