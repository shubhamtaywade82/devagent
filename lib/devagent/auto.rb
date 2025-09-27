# frozen_string_literal: true

require "tty-reader"
require "tty-box"
require "tty-spinner"
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
      output.puts(greeting_banner)
    end

    def farewell
      output.puts("Goodbye!")
      :exited
    end

    def exit_command?(command)
      EXIT_COMMANDS.include?(command.downcase)
    end

    def run(task)
      plan = with_spinner("Planning") { Planner.plan(ctx: @context, task: task) }
      output.puts("Planning confidence: #{plan.confidence.round(2)}")

      if plan.actions.empty?
        # Instead of stopping, fall back to Q&A
        output.puts("No actions planned. Asking model directly...")
        answer = with_spinner("Consulting model") { @context.llm.call(task) }
        output.puts(answer)
        return
      end

      output.puts("Executing…")
      iterate(task, plan)
    end

    def iterate(task, plan)
      (1..@max_iter).each do |i|
        output.puts("Iteration #{i}/#{@max_iter}")
        with_spinner("Applying actions") { @executor.apply(plan.actions) }
        @executor.log.each { |line| output.puts("  -> #{line}") }

        @context.plugins.each { |p| p.on_post_edit(@context, @executor.log.join("\n")) if p.respond_to?(:on_post_edit) }

        # Only run tests if we actually changed code (or asked to generate tests)
        changed_code = @executor.changes_made?
        status = if changed_code
                   with_spinner("Running tests") { run_tests }
                 else
                   :skipped
                 end

        case status
        when :green
          @executor.finalize_success!("devagent: #{task}")
          output.puts("✅ Tests green. Changes committed.")
          return
        when :skipped
          # No code change or no tests detected; don't pretend success with a commit
          output.puts("ℹ️ No tests run (no test framework detected or no code changes).")
          return
        else
          output.puts("Tests red. Replanning…")
          feedback = gather_feedback
          plan = replan(task, feedback)
        end
      end

      output.puts("❌ Could not get green within #{@max_iter} iterations. Check git diff and logs.")
    end

    def run_tests
      ran_any = false
      ok_any  = false

      # Try Rails, Gem, React – only count success if a runner actually ran
      %w[rails:test gem:test react:test].each do |name|
        if try_action_safe(name)
          ran_any = true
          ok_any  = ($?.respond_to?(:success?) && $?.success?) || ok_any
        end
      end

      return :skipped unless ran_any
      ok_any ? :green : :red
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
          return true if res # treat truthy as “runner executed”
        rescue => e
          @executor.log << "test action #{name} failed: #{e.message}"
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
      raw = with_spinner("Replanning") do
        @context.llm.call(preface + "\nTask:\n" + task + "\nReturn JSON only.")
      end
      json = JSON.parse(raw) rescue {"confidence" => 0.0, "actions" => []}
      Plan.new(json["actions"] || [], (json["confidence"] || 0.0).to_f)
    end

    def with_spinner(message)
      spinner = TTY::Spinner.new(
        "[:spinner] #{message}...",
        format: :dots,
        output: output,
        clear: true
      )
      spinner.auto_spin
      yield
    ensure
      spinner&.stop
    end

    def greeting_banner
      lines = ["Devagent autonomous REPL. Type 'exit' to quit."]
      lines.concat(survey_summary_lines)

      TTY::Box.frame(
        lines.join("\n"),
        align: :left,
        padding: [1, 2],
        title: { top_left: "Devagent" }
      )
    end

    def survey_summary_lines
      survey = context.respond_to?(:survey) ? context.survey : nil
      return [] unless survey

      lines = []
      lines << "Structure: #{survey.structure_lines.join(', ')}" if survey.structure_lines.any?
      lines << "Key files: #{survey.key_file_lines.join(', ')}" if survey.key_file_lines.any?
      if survey.doc_previews.any?
        doc_list = survey.doc_previews.keys.join(', ')
        lines << "Docs: #{doc_list}"
      end

      lines
    end
  end
end
