# frozen_string_literal: true

require "tty-reader"
require_relative "planner"
require_relative "executor"

module Devagent
  # Auto exposes the interactive REPL that drives autonomous workflows.
  class Auto
    PROMPT = "devagent> "
    EXIT_COMMANDS = %w[exit quit].freeze

    def initialize(context, input: $stdin, output: $stdout)
      @context = context
      @input = input
      @output = output
      @executor = Executor.new(context)
      @max_iter = context.config.dig("auto", "max_iterations") || 3
      @require_green = context.config.dig("auto", "require_tests_green") != false
      @threshold = context.config.dig("auto", "confirmation_threshold") || 0.7

      # build index once, allow plugins to tune it
      context.plugins.each { |p| p.on_index(context) if p.respond_to?(:on_index) }
      context.index.build!
    end

    def repl
      greet

      reader = TTY::Reader.new
      loop do
        command = reader.read_line(PROMPT)
        break if command.nil? || exit_command?(command.strip)

        run(command.strip)
      end

      farewell
    end

    private

    attr_reader :context, :input, :output

    def greet
      output.puts("Devagent autonomous REPL. Type 'exit' to quit.")
    end

    def farewell
      output.puts("Goodbye!")
      :exited
    end

    def exit_command?(command)
      EXIT_COMMANDS.include?(command.downcase)
    end

    def run(task)
      plan = Planner.plan(ctx: @context, task: task)
      output.puts("Planning confidence: #{plan.confidence.round(2)}")
      output.puts("Executing…")
      iterate(task, plan)
    end

    def iterate(task, plan)
      (1..@max_iter).each do |i|
        output.puts("Iteration #{i}/#{@max_iter}")
        @executor.apply(plan.actions)

        # plugin post-processing (formatters, etc.)
        @context.plugins.each { |p| p.on_post_edit(@context, @executor.log.join("\n")) if p.respond_to?(:on_post_edit) }

        status = run_tests
        if status == :green
          @executor.finalize_success!("devagent: #{task}")
          output.puts("✅ Tests green. Changes committed.")
          return
        end

        output.puts("Tests red. Replanning…")
        feedback = gather_feedback
        plan = replan(task, feedback)
      end

      output.puts("❌ Could not get green within #{@max_iter} iterations. Check git diff and logs.")
    end

    def run_tests
      return :green if try_action_safe("rails:test")
      return :green if try_action_safe("gem:test")
      return :green if try_action_safe("react:test")
      :red
    end

    def try_action(name)
      @context.plugins.each do |p|
        if p.respond_to?(:on_action)
          res = p.on_action(@context, name, {})
          return res if res
        end
      end
      nil
    end

    def try_action_safe(name)
      @context.plugins.each do |p|
        next unless p.respond_to?(:on_action)
        begin
          res = p.on_action(@context, name, {})
          # If the plugin ran tests successfully, shell.call didn’t raise.
          return true if res
        rescue => e
          @executor.log << "test action #{name} failed: #{e.message}"
          # keep trying other runners
        end
      end
      false
    end

    def gather_feedback
      diff = `git -C #{@context.repo_path} diff --unified`.to_s
      rspec_log = File.exist?(File.join(@context.repo_path, "tmp", "rspec_failures.txt")) ? File.read(File.join(@context.repo_path, "tmp", "rspec_failures.txt")) : ""
      [diff, rspec_log].join("\n\n")
    end

    def replan(task, feedback)
      preface = <<~P
      #{Planner::SYSTEM}
      Previous attempt had failures. Use this feedback to fix:
      #{feedback}
      P
      raw = @context.llm.call(preface + "\nTask:\n" + task + "\nReturn JSON only.")
      json = JSON.parse(raw) rescue {"confidence" => 0.0, "actions" => []}
      Plan.new(json["actions"] || [], (json["confidence"] || 0.0).to_f)
    end
  end
end
