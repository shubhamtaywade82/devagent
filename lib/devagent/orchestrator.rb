# frozen_string_literal: true

require_relative "planner"
require_relative "prompts"
require_relative "streamer"
require_relative "ui"

module Devagent
  # Orchestrator coordinates planning, execution, and testing loops.
  class Orchestrator
    attr_reader :context, :planner, :streamer, :ui

    def initialize(context, output: $stdout, ui: UI::Toolkit.new(output: output))
      @context = context
      @ui = ui
      @streamer = Streamer.new(context, output: output, ui: ui)
      @planner = Planner.new(context, streamer: @streamer)
    end

    def run(task)
      context.session_memory.append("user", task)
      ui.spinner("Updating embedding index").run { context.index.build! }
      plan = planner.plan(task)
      context.tracer.event("plan", summary: plan.summary, confidence: plan.confidence, actions: plan.actions)
      streamer.say("Plan confidence #{plan.confidence.round(2)}: #{plan.summary}") if plan.summary
      return finish("Nothing to do (confidence #{plan.confidence.round(2)})") if plan.actions.empty?

      if ui.interactive?
        proceed = ui.prompt.confirm("Execute #{plan.actions.size} action(s)?", default: true)
        unless proceed
          streamer.say("Plan aborted by user.", level: :warn)
          return
        end
      end

      iterations = context.config.dig("auto", "max_iterations") || 3
      iterations.times do |iteration|
        streamer.say("Iteration #{iteration + 1}/#{iterations}")
        context.tool_bus.reset!
        execute_actions(plan.actions)
        break unless retry_needed?(iteration)
        plan = planner.plan(task)
      end
    end

    private

    def execute_actions(actions)
      actions.each do |action|
        context.tracer.event("execute_action", action: action)
        context.tool_bus.invoke(action)
      rescue StandardError => e
        streamer.say("Action #{action["type"]} failed: #{e.message}")
        break
      end
    end

    def retry_needed?(iteration)
      if context.tool_bus.changes_made? && should_run_tests?
        result = ui.spinner("Running tests").run { run_tests }
        return false if result == :ok
        if result == :skipped
          streamer.say("Tests skipped (no command available).")
          return false
        end

        streamer.say("Tests failed, replanning…")
        context.session_memory.append("assistant", "Tests failed on iteration #{iteration + 1}")
        context.tracer.event("tests_failed")
        return iteration + 1 < (context.config.dig("auto", "max_iterations") || 3)
      end

      streamer.say("No changes detected; stopping.") unless context.tool_bus.changes_made?
      false
    end

    def run_tests
      command = context.plugins.filter_map { |plugin| plugin.respond_to?(:test_command) ? plugin.test_command(context) : nil }.first
      command ||= "bundle exec rspec"
      context.tool_bus.run_tests("command" => command)
    rescue StandardError => e
      streamer.say("Test command failed: #{e.message}")
      :failed
    end

    def finish(message)
      streamer.say(message)
    end

    def should_run_tests?
      context.config.dig("auto", "require_tests_green") != false
    end
  end
end
