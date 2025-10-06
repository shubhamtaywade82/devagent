# frozen_string_literal: true

require_relative "planner"
require_relative "prompts"
require_relative "streamer"
require_relative "ui"

module Devagent
  # Orchestrator coordinates planning, execution, and testing loops.
  class Orchestrator
    attr_reader :context, :planner, :streamer, :ui

    def initialize(context, output: $stdout, ui: nil)
      @context = context
      @ui = ui || UI::Toolkit.new(output: output)
      @streamer = Streamer.new(context, output: output, ui: @ui)
      @planner = Planner.new(context, streamer: @streamer)
    end

    def run(task)
      context.session_memory.append("user", task)
      with_spinner("Indexing") { context.index.build! }
      return answer_unactionable(task, 1.0) if qna?(task)

      plan = with_spinner("Planning") { planner.plan(task) }
      context.tracer.event("plan", summary: plan.summary, confidence: plan.confidence, actions: plan.actions)
      streamer.say("Plan: #{plan.summary} (#{(plan.confidence * 100).round}%)") if plan.summary && !quiet?
      return answer_unactionable(task, plan.confidence) if plan.actions.empty?

      iterations = context.config.dig("auto", "max_iterations") || 3
      iterations.times do |iteration|
        streamer.say("Iteration #{iteration + 1}/#{iterations}") unless quiet?
        context.tool_bus.reset!
        execute_actions(plan.actions)
        break unless retry_needed?(iteration, task, plan.confidence)

        plan = with_spinner("Planning") { planner.plan(task) }
      end
    end

    private

    def execute_actions(actions)
      actions.each do |action|
        context.tracer.event("execute_action", action: action)
        context.tool_bus.invoke(action)
      rescue StandardError => e
        streamer.say("Action #{action["type"]} failed: #{e.message}", level: :error)
        break
      end
    end

    def retry_needed?(iteration, task, confidence)
      if context.tool_bus.changes_made? && should_run_tests?
        result = with_spinner("Running tests") { run_tests }
        return false if result == :ok

        if result == :skipped
          streamer.say("Tests skipped (no command available).", level: :warn) unless quiet?
          return false
        end

        streamer.say("Tests failed, replanning…", level: :warn) unless quiet?
        context.session_memory.append("assistant", "Tests failed on iteration #{iteration + 1}")
        context.tracer.event("tests_failed")
        return iteration + 1 < (context.config.dig("auto", "max_iterations") || 3)
      end

      unless context.tool_bus.changes_made?
        streamer.say("No changes detected; answering directly.") unless quiet?
        answer_unactionable(task, confidence)
      end
      false
    end

    def run_tests
      command = context.plugins.filter_map do |plugin|
        plugin.respond_to?(:test_command) ? plugin.test_command(context) : nil
      end.first
      command ||= "bundle exec rspec"
      context.tool_bus.run_tests("command" => command)
    rescue StandardError => e
      streamer.say("Test command failed: #{e.message}", level: :error)
      :failed
    end

    def finish(message)
      streamer.say(message)
    end

    def should_run_tests?
      context.config.dig("auto", "require_tests_green") != false
    end

    # When planning yields no actions, answer the user's question directly using
    # the developer model and light repository context.
    def answer_unactionable(task, confidence)
      streamer.say("Answer:") unless quiet?
      prompt = build_answer_prompt(task)
      answer = with_spinner("Answering") do
        context.query(
          role: :developer,
          prompt: prompt,
          stream: false
        )
      end
      streamer.say(answer.to_s.strip, markdown: true)
    rescue Exception => e
      raise if e.is_a?(Interrupt)

      streamer.say("Answering failed: #{e.message}") unless quiet?
    end

    def quiet?
      context.config.dig("ui", "quiet") == true
    end

    def build_answer_prompt(task)
      retrieved = safe_index_retrieve(task, limit: 6).map do |snippet|
        "#{snippet["path"]}:\n#{snippet["text"]}\n---"
      end.join("\n")

      history = safe_session_history(limit: 6).map do |turn|
        "#{turn["role"]}: #{turn["content"]}"
      end.join("\n")

      <<~PROMPT
        You are a concise, helpful developer assistant.
        If the question relates to this repository, use the context below; otherwise answer generally.

        Recent conversation:
        #{history}

        Repository context:
        #{retrieved}

        Question:
        #{task}
      PROMPT
    end

    def qna?(task)
      text = task.to_s.strip.downcase
      return true if text.end_with?("?")

      q_words = %w[what who when where why how explain describe summarize tell show list hi hello hey help]
      return true if q_words.any? { |w| text.start_with?("#{w} ") || text == w }

      action_words = %w[add create update implement refactor fix write generate run install build change edit remove
                        delete migrate release publish configure set enable disable]
      return false if action_words.any? { |w| text.include?(" #{w} ") || text.start_with?(w) }

      false
    end

    def safe_index_retrieve(task, limit: 6)
      context.index.retrieve(task, limit: limit)
    rescue Exception => e
      raise if e.is_a?(Interrupt)

      context.tracer.event("index_retrieve_failed", message: e.message)
      []
    end

    def safe_session_history(limit: 6)
      context.session_memory.last_turns(limit)
    rescue Exception => e
      raise if e.is_a?(Interrupt)

      context.tracer.event("session_history_failed", message: e.message)
      []
    end

    def with_spinner(label)
      if ui&.respond_to?(:spinner)
        ui.spinner(label).run { yield }
      else
        yield
      end
    end
  end
end
