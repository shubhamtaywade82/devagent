# frozen_string_literal: true

require_relative "orchestrator"
require_relative "ui"
require_relative "history"

module Devagent
  # Auto provides a simple REPL shell for the autonomous agent.
  class Auto
    PROMPT = "devagent> "
    EXIT = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout, ui: nil)
      @context = context
      @input = input
      @output = output
      @history = History.new(context.repo_path)
      @ui = ui || UI::Toolkit.new(output: output, input: input)
      @reader = @ui.reader(history: @history)
      @orchestrator = Orchestrator.new(context, output: output, ui: @ui)
    end

    def repl
      log(:info, "Devagent ready. Type 'exit' to quit.")
      # Initialize Readline history
      reader.update_history
      loop do
        line = reader.read_line(PROMPT)
        break if line.nil? || EXIT.include?(line.strip.downcase)
        next if line.strip.empty?

        if line.strip.downcase == "start"
          log(:info, "Already running the REPL.")
          next
        end

        # History is automatically managed by reader.read_line
        # It adds to persistent storage and updates Readline history

        begin
          orchestrator.run(line.strip)
        rescue StandardError => e
          log(:error, "Error: #{e.message}")
          context.tracer.event("repl_error", message: e.message)
        end
      rescue Interrupt
        log(:warn, "^C")
      end

      log(:success, "Goodbye!")
      :exited
    end

    private

    attr_reader :context, :reader, :output, :orchestrator, :ui, :history

    def log(level, message)
      if ui&.respond_to?(:logger)
        ui.logger.public_send(level, message)
      else
        output.puts(message)
      end
    end
  end
end
