# frozen_string_literal: true

require_relative "orchestrator"
require_relative "ui"

module Devagent
  # Auto provides a simple REPL shell for the autonomous agent.
  class Auto
    PROMPT = "devagent> "
    EXIT = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout)
      @context = context
      @input = input
      @output = output
      @ui = UI::Toolkit.new(output: output, input: input)
      @reader = ui.reader
      @orchestrator = Orchestrator.new(context, output: output, ui: ui)
    end

    def repl
      output.puts(ui.colorizer.colorize(:info, "Devagent ready. Type 'exit' to quit."))
      loop do
        line = reader.read_line(PROMPT)
        break if line.nil? || EXIT.include?(line.strip.downcase)
        next if line.strip.empty?

        orchestrator.run(line.strip)
      rescue TTY::Reader::InputInterrupt, Interrupt
        output.puts(ui.colorizer.colorize(:warn, "^C"))
      rescue StandardError => e
        output.puts(ui.colorizer.colorize(:error, "Error: #{e.message}"))
        context.tracer.event("repl_error", message: e.message)
      end

      output.puts(ui.colorizer.colorize(:info, "Goodbye!"))
      :exited
    end

    private

    attr_reader :context, :reader, :output, :orchestrator, :ui
  end
end
