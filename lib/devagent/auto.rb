# frozen_string_literal: true

require "tty-reader"
require_relative "planner"
require_relative "executor"
require_relative "safety"

module Devagent
  class Auto
    PROMPT = "devagent> "
    EXIT_COMMANDS = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout)
      @context = context
      @input = input
      @output = output
      @executor = Executor.new(context)
      @safety = Safety.new(context)
    end

    def repl
      output.puts("Devagent REPL (actions+chat). Type 'exit' to quit.")
      reader = TTY::Reader.new
      loop do
        line = reader.read_line(PROMPT)
        break if line.nil?
        cmd = line.strip
        break if EXIT_COMMANDS.include?(cmd.downcase)
        handle(cmd)
      end
      output.puts("Goodbye!")
    end

    private

    attr_reader :context, :input, :output, :safety

    def handle(task)
      plan = Planner.plan(ctx: context, task: task)
      if plan.actions.empty?
        ask(task)
        return
      end

      confidence = plan.confidence.to_f
      threshold = confirmation_threshold
      if confidence < threshold
        output.puts("Plan confidence %.2f below %.2f; answering directly." % [confidence, threshold])
        ask(task)
        return
      end

      unless allowed_actions?(plan.actions)
        output.puts("Plan requested paths outside the allowlist; falling back to chat instead.")
        ask(task)
        return
      end

      # Execute actions
      begin
        @executor.apply(plan.actions)
        @executor.log.each { |line| output.puts("  -> #{line}") }
        output.puts("✅ Done.")
      rescue => e
        handled = handle_execution_error(task, e)
        output.puts("❌ Execution error: #{e.message}") unless handled
      end
    end

    def handle_execution_error(original_task, error)
      return false unless error.to_s.include?("path not allowed")

      output.puts("Tip: add that path to `.devagent.yml` allowlist or use a different location. Falling back to chat...")
      ask(original_task)
      true
    end

    def confirmation_threshold
      (context.config.dig("auto", "confirmation_threshold") || 0.0).to_f
    end

    def allowed_actions?(actions)
      Array(actions).all? do |action|
        next true unless %w[create_file edit_file].include?(action["type"])
        path = action["path"].to_s
        !path.empty? && safety.allowed?(path)
      end
    end


    def ask(text)
      answer = context.llm.call(text)
      output.puts(answer.to_s)
    rescue => e
      output.puts("LLM error: #{e.message}")
      output.puts("Tip: choose a smaller or quantized Ollama model in `.devagent.yml` and ensure it is pulled with `ollama pull <model>`.")
      output.puts("      Export `OLLAMA_HOST` if the Ollama server runs on another host.")
    end

  end
end
