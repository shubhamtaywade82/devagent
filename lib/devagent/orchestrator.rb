# frozen_string_literal: true

require_relative "planner"
require_relative "prompts"
require_relative "streamer"
require_relative "ui"
require_relative "agent_state"
require_relative "intent_classifier"

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
      state = AgentState.initial(goal: task)

      intent = with_spinner("Classifying") { IntentClassifier.new(context).classify(task) }
      state.intent = intent["intent"]
      state.intent_confidence = intent["confidence"].to_f
      context.tracer.event("intent", intent: state.intent, confidence: state.intent_confidence)

      if %w[EXPLANATION GENERAL].include?(state.intent)
        return answer_unactionable(task, state.intent_confidence, use_repo_context: false)
      end
      return answer_unactionable(task, state.intent_confidence, use_repo_context: false) if state.intent == "REJECT"

      with_spinner("Indexing") { context.index.build! }

      max_cycles = context.config.dig("auto", "max_iterations") || 3
      state.phase = :planning

      while !%i[done halted].include?(state.phase)
        case state.phase
        when :planning
          visible_tools = if context.tool_registry.respond_to?(:tools_for_phase)
                            context.tool_registry.tools_for_phase(:planning).values
                          else
                            context.tool_registry.tools.values
                          end

          plan = with_spinner("Planning") do
            planner.plan(task, controller_feedback: controller_feedback(state), visible_tools: visible_tools)
          end

          state.plan = plan
          context.tracer.event("plan", summary: plan.summary, confidence: plan.confidence, actions: plan.actions)
          streamer.say("Plan: #{plan.summary} (#{(plan.confidence * 100).round}%)") if plan.summary && !quiet?

          if plan.actions.empty?
            state.phase = :done
            answer_unactionable(task, plan.confidence)
            next
          end

          state.phase = :execution

        when :execution
          state.cycle += 1
          streamer.say("Cycle #{state.cycle}/#{max_cycles}") unless quiet?
          context.tool_bus.reset!
          execute_actions(state, state.plan.actions)
          state.phase = :observation

        when :observation
          observe_after_execution(state)
          state.phase = :reduction

        when :reduction
          state.summary = reduce_state(state)
          context.tracer.event("reduction", summary: state.summary)
          state.phase = :decision

        when :decision
          if hard_stop?(state, max_cycles: max_cycles)
            state.phase = :halted
            streamer.say("Halting: no progress / repeated failure detected.", level: :warn) unless quiet?
            next
          end

          decision_next_phase(state, task, max_cycles: max_cycles)
        else
          state.phase = :halted
        end
      end
    end

    private

    def execute_actions(state, actions)
      actions.each do |action|
        context.tracer.event("execute_action", action: action)
        execute_action_with_policy(state, action)
      rescue StandardError => e
        streamer.say("Action #{action["type"]} failed: #{e.message}", level: :error)
        state.record_error(signature: "action_failed:#{action["type"]}", message: e.message)
        state.record_observation({ "type" => "ACTION_FAILED", "tool" => action["type"], "message" => e.message })
        break
      end
    end

    def execute_action_with_policy(state, action)
      name = action.fetch("type")
      args = action.fetch("args", {}) || {}

      tool = context.tool_registry.fetch(name)
      raise Error, "Unknown tool #{name}" unless tool

      allowed = tool.allowed_phases.nil? || Array(tool.allowed_phases).map(&:to_sym).include?(state.phase)
      unless allowed
        state.tool_rejections += 1
        state.record_observation({ "type" => "TOOL_REJECTED", "tool" => name, "reason" => "forbidden_in_phase" })
        raise Error, "Tool #{name} forbidden in phase #{state.phase}"
      end

      if name == "fs_write"
        path = args["path"]
        unless state.artifacts[:files_read].include?(path.to_s)
          state.tool_rejections += 1
          state.record_observation({ "type" => "TOOL_REJECTED", "tool" => name, "reason" => "missing_dependency",
                                     "depends_on" => "fs_read", "path" => path })
          raise Error, "Tool #{name} requires fs_read of #{path} first"
        end
      end

      result = context.tool_bus.invoke(action)
      case name
      when "fs_read"
        state.record_file_read(args["path"])
        state.record_observation({ "type" => "FILE_READ", "path" => args["path"], "bytes" => result.to_s.bytesize })
      when "fs_write"
        state.record_file_written(args["path"])
        state.record_observation({ "type" => "FILE_WRITTEN", "path" => args["path"] })
      when "git_apply"
        state.record_patch_applied
        state.record_observation({ "type" => "PATCH_APPLIED" })
      when "run_command"
        state.record_command(args["command"])
        state.record_observation({ "type" => "COMMAND_RAN", "command" => args["command"] })
      when "run_tests"
        state.record_observation({ "type" => "TESTS_REQUESTED", "command" => args["command"] })
      end

      result
    end

    def observe_after_execution(state)
      return state.record_observation({ "type" => "NO_CHANGES" }) unless context.tool_bus.changes_made?
      return state.record_observation({ "type" => "TESTS_SKIPPED" }) unless should_run_tests?

      result = with_spinner("Running tests") { run_tests }
      case result
      when :ok
        state.record_observation({ "type" => "TEST_RESULT", "status" => "PASS" })
      when :skipped
        state.record_observation({ "type" => "TEST_RESULT", "status" => "SKIP" })
      else
        state.record_observation({ "type" => "TEST_RESULT", "status" => "FAIL" })
      end
    rescue StandardError => e
      state.record_error(signature: "tests_failed", message: e.message)
      state.record_observation({ "type" => "TEST_RESULT", "status" => "FAIL", "message" => e.message })
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
    def answer_unactionable(task, confidence, use_repo_context: true)
      streamer.say("Answer:") unless quiet?
      prompt = build_answer_prompt(task, use_repo_context: use_repo_context)
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

    def build_answer_prompt(task, use_repo_context:)
      retrieved = if use_repo_context
                    safe_index_retrieve(task, limit: 6).map do |snippet|
                      "#{snippet["path"]}:\n#{snippet["text"]}\n---"
                    end.join("\n")
                  else
                    ""
                  end

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

    def controller_feedback(state)
      recent = state.observations.last(8)
      errs = state.errors.last(2)
      parts = []
      parts << "Recent observations: #{recent.map { |o| o["type"] }.join(", ")}" unless recent.empty?
      parts << "Recent errors: #{errs.map { |e| e["signature"] }.join(", ")}" unless errs.empty?
      parts.join("\n")
    end

    def reduce_state(state)
      changed = state.artifacts[:files_written].to_a
      obs = state.observations.last(10).map { |o| o["type"] }
      last_test = obs.grep(/TEST/).last || "none"
      "changed_files=#{changed.size} tests=#{last_test} observations=#{obs.join(",")}"
    end

    def decision_next_phase(state, task, max_cycles:)
      if state.observations.any? { |o| o["type"] == "TEST_RESULT" && o["status"] == "FAIL" }
        streamer.say("Tests failed, replanning…", level: :warn) unless quiet?
        context.session_memory.append("assistant", "Tests failed on cycle #{state.cycle}")
        context.tracer.event("tests_failed")
        state.phase = state.cycle < max_cycles ? :planning : :halted
        return
      end

      if state.observations.any? { |o| o["type"] == "NO_CHANGES" }
        streamer.say("No changes detected; answering directly.") unless quiet?
        answer_unactionable(task, state.plan&.confidence.to_f)
        state.phase = :done
        return
      end

      state.confidence = 1.0
      state.phase = :done
    end

    def hard_stop?(state, max_cycles:)
      return true if state.tool_rejections >= 2
      return true if state.repeat_error_count >= 2
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
