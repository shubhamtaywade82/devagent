# frozen_string_literal: true

require "tty-reader"
require_relative "planner"
require_relative "executor"

module Devagent
  class Auto
    PROMPT = "devagent> "
    EXIT_COMMANDS = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout)
      @context = context
      @input = input
      @output = output
      @executor = Executor.new(context)
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

    attr_reader :context, :input, :output

    def handle(task)
      plan = Planner.plan(ctx: context, task: task)
      if plan.actions.empty?
        # Q&A fallback
        answer = context.llm.call(task)
        output.puts(answer.to_s)
        return
      end

      # Execute actions
      begin
        @executor.apply(plan.actions)
        @executor.log.each { |line| output.puts("  -> #{line}") }
        output.puts("✅ Done.")
      rescue => e
        output.puts("❌ Execution error: #{e.message}")
      end
    end
  end
end
