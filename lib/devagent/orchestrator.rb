# frozen_string_literal: true

require_relative "planner"
require_relative "prompts"
require_relative "streamer"
require_relative "ui"
require_relative "agent_state"
require_relative "intent_classifier"
require_relative "diff_generator"
require_relative "decision_engine"
require_relative "success_verifier"

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
        # Check if the question requires running a command (e.g., "is this rubocop offenses free?")
        if question_requires_command?(task)
          # Allow EXPLANATION questions that need commands to go through planning
          # This enables run_command to be used for checking tools like rubocop, tests, etc.
        else
          # Use repo context if the question is about the repository
          use_repo_context = question_about_repo?(task)
          with_spinner("Indexing") { context.index.build! } if use_repo_context
          return answer_unactionable(task, state.intent_confidence, use_repo_context: use_repo_context)
        end
      end
      return answer_unactionable(task, state.intent_confidence, use_repo_context: false) if state.intent == "REJECT"

      with_spinner("Indexing") { context.index.build! }

      max_cycles = context.config.dig("auto", "max_iterations") || 3
      state.phase = :planning

      until %i[done halted].include?(state.phase)
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
          context.tracer.event("plan", plan_id: plan.plan_id, goal: plan.goal, confidence: plan.confidence,
                                       steps: plan.steps)
          streamer.say("Plan: #{plan.goal} (#{(plan.confidence * 100).round}%)") if plan.goal && !quiet?

          begin
            validate_plan!(state, plan, visible_tools: visible_tools)
          rescue StandardError => e
            state.record_error(signature: "plan_rejected", message: e.message)
            state.record_observation({ "type" => "PLAN_REJECTED", "message" => e.message })
            state.phase = :decision
            next
          end

          if plan.steps.empty?
            state.phase = :done
            answer_unactionable(task, plan.confidence)
            next
          end

          state.phase = :execution

        when :execution
          state.cycle += 1
          streamer.say("Cycle #{state.cycle}/#{max_cycles}") unless quiet?
          context.tool_bus.reset!
          execute_plan(state)
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

    def execute_plan(state)
      plan = state.plan
      total = plan.steps.size
      plan.steps.each do |step|
        state.current_step = step["step_id"].to_i
        unless quiet?
          streamer.say("[#{state.current_step}/#{total}] #{step["action"]} #{step["path"] || step["command"]}".strip)
        end
        ensure_dependencies!(step, state.step_results)
        result = execute_step(state, plan, step)
        state.step_results[step["step_id"]] = result
        state.record_observation(normalize_step_observation(result, step))
        raise Error, "step #{step["step_id"]} failed" unless result["success"]
      rescue StandardError => e
        streamer.say("Step #{step["step_id"]} failed: #{e.message}", level: :error)
        state.record_error(signature: "step_failed:#{step["step_id"]}", message: e.message)
        state.step_results[step["step_id"]] = { "success" => false, "error" => e.message }
        state.record_observation({ "type" => "STEP_FAILED", "step_id" => step["step_id"], "status" => "FAIL",
                                   "error" => e.message })
        break
      end
    end

    def ensure_dependencies!(step, results)
      Array(step["depends_on"]).each do |dep|
        next if dep.to_i == 0

        res = results[dep]
        raise Error, "Dependency #{dep} not satisfied" unless res && res["success"]
      end
    end

    def execute_step(state, plan, step)
      action = step["action"].to_s
      path = step["path"]
      command = step["command"]

      case action
      when "fs_read"
        tool_invoke_with_policy(state, "fs_read", "path" => path)
      when "fs_write"
        # diff-first write: read must have happened, then generate diff, then apply diff.
        raise Error, "path required" if path.to_s.empty?

        ensure_read_same_path!(state, path)
        original = context.tool_bus.read_file("path" => path.to_s)
        diff = DiffGenerator.new(context).generate(path: path.to_s, original: original, goal: plan.goal.to_s,
                                                   reason: step["reason"].to_s)
        tool_invoke_with_policy(state, "fs_write_diff", "path" => path.to_s, "diff" => diff)
      when "fs_delete"
        raise Error, "path required" if path.to_s.empty?

        ensure_read_same_path!(state, path)
        tool_invoke_with_policy(state, "fs_delete", "path" => path.to_s)
      when "run_tests"
        tool_invoke_with_policy(state, "run_tests", "command" => command)
      when "run_command"
        tool_invoke_with_policy(state, "run_command", "command" => command)
      else
        raise Error, "Unknown step action #{action}"
      end
    end

    def tool_invoke_with_policy(state, tool_name, args)
      tool = context.tool_registry.fetch(tool_name)
      raise Error, "Unknown tool #{tool_name}" unless tool

      allowed = tool.allowed_phases.nil? || Array(tool.allowed_phases).map(&:to_sym).include?(state.phase)
      unless allowed
        state.tool_rejections += 1
        raise Error, "Tool #{tool_name} forbidden in phase #{state.phase}"
      end

      result = context.tool_bus.invoke("type" => tool_name, "args" => args)
      record_artifacts(state, tool_name, args, result)
      { "success" => true, "artifact" => result }
    end

    def record_artifacts(state, tool_name, args, result)
      case tool_name
      when "fs_read"
        state.record_file_read(args["path"], meta: file_meta(args["path"]))
      when "fs_write_diff"
        state.record_file_written(args["path"])
      when "git_apply"
        state.record_patch_applied
      when "run_command"
        state.record_command(args["command"])
      when "run_tests"
        state.record_observation({ "type" => "TESTS_REQUESTED", "command" => args["command"] })
      end
    end

    def ensure_read_same_path!(state, path)
      p = path.to_s
      raise Error, "fs_write requires prior fs_read of #{p}" unless state.artifacts[:files_read].include?(p)

      meta = state.files_read_meta[p]
      return if meta.nil? # best-effort; e.g. file didn't exist

      current = file_meta(p)
      raise Error, "file changed since read: #{p}" unless current["mtime"].to_f == meta["mtime"].to_f
    end

    def file_meta(relative_path)
      full = File.join(context.repo_path, relative_path.to_s)
      return { "mtime" => 0.0, "size" => 0 } unless File.exist?(full)

      st = File.stat(full)
      { "mtime" => st.mtime.to_f, "size" => st.size }
    rescue StandardError
      { "mtime" => 0.0, "size" => 0 }
    end

    def normalize_step_observation(result, step)
      {
        "type" => step["action"].to_s.upcase,
        "step_id" => step["step_id"],
        "status" => result["success"] ? "OK" : "FAIL",
        "artifact" => result["artifact"],
        "error" => result["error"]
      }
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

      # Include directory structure if the question is about directory structure
      dir_structure = if question_about_directory_structure?(task)
                        get_directory_structure
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

        #{"Directory structure:\n#{dir_structure}\n\n" unless dir_structure.empty?}Repository context:
        #{retrieved.empty? ? "(none)" : retrieved}

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
      decision = DecisionEngine.new(context).decide(
        plan: plan_payload(state.plan),
        step_results: state.step_results,
        observations: state.observations.last(30)
      )

      if state.last_decision && state.last_decision == decision["decision"]
        state.phase = :halted
        streamer.say("Halting: repeated decision #{decision["decision"]}.", level: :warn) unless quiet?
        return
      end

      if state.last_decision_confidence && decision["confidence"].to_f < state.last_decision_confidence.to_f
        state.phase = :halted
        streamer.say("Halting: decision confidence decreased.", level: :warn) unless quiet?
        return
      end

      state.last_decision = decision["decision"]
      state.last_decision_confidence = decision["confidence"].to_f

      case decision["decision"]
      when "SUCCESS"
        begin
          SuccessVerifier.verify!(
            criteria: state.plan.success_criteria,
            observations: state.observations,
            artifacts: state.artifacts
          )
        rescue StandardError => e
          streamer.say("Success criteria not met: #{e.message}", level: :warn) unless quiet?
          state.phase = state.cycle < max_cycles ? :planning : :halted
          return
        end

        state.confidence = decision["confidence"].to_f
        state.phase = :done
      when "RETRY"
        streamer.say("Retrying: #{decision["reason"]}", level: :warn) unless quiet?
        state.phase = state.cycle < max_cycles ? :planning : :halted
      else
        reason = decision["reason"].to_s
        if !state.clarification_asked && reason.match?(/missing|unclear|unknown/i)
          state.clarification_asked = true
          streamer.say("Clarification needed: #{reason}", level: :warn) unless quiet?
          streamer.say("Please answer the question above and rerun.", level: :warn) unless quiet?
        else
          streamer.say("Blocked: #{reason}", level: :warn) unless quiet?
        end
        state.phase = :halted
      end
    end

    def hard_stop?(state, max_cycles:)
      return true if state.tool_rejections >= 2
      return true if state.repeat_error_count >= 2

      false
    end

    def validate_plan!(state, plan, visible_tools:)
      raise Error, "plan confidence too low" if plan.confidence.to_f < 0.5

      allowed = Array(visible_tools).map(&:name)
      # Also check all tools in registry (for run_command/run_tests that might not be in visible_tools)
      all_tool_names = context.tool_registry.tools.keys
      allowed_names = (allowed + all_tool_names).uniq

      step_actions = plan.steps.map { |s| s["action"].to_s }
      # fs_write is a logical action that gets converted to fs_write_diff
      # run_command and run_tests are always allowed for command execution
      unknown = step_actions.reject do |a|
        allowed_names.include?(a) || a == "fs_write" || a == "run_command" || a == "run_tests"
      end
      raise Error, "plan uses unknown tools: #{unknown.uniq.join(", ")}" unless unknown.empty?

      # Read scope limiter: first cycle may read at most one file.
      # Exception: if plan only contains commands (no file operations), allow it
      command_only = plan.steps.all? { |s| %w[run_command run_tests].include?(s["action"].to_s) }
      if state.cycle.to_i == 0 && !command_only
        reads = plan.steps.count { |s| s["action"].to_s == "fs_read" }
        raise Error, "too many reads in first plan" if reads > 1
      end

      fp = fingerprint_plan(plan)
      raise Error, "plan repeated without progress" if state.plan_fingerprints.include?(fp)

      state.plan_fingerprints << fp

      # Enforce: every fs_write depends on a prior fs_read of the same path.
      reads = {}
      plan.steps.each do |s|
        reads[s["step_id"]] = s["path"].to_s if s["action"] == "fs_read"
      end

      plan.steps.each do |s|
        next unless s["action"] == "fs_write"

        path = s["path"].to_s
        deps = Array(s["depends_on"]).map(&:to_i)
        dep_paths = deps.filter_map { |id| reads[id] }
        raise Error, "fs_write must depend_on prior fs_read of same path (#{path})" unless dep_paths.include?(path)
      end
    end

    def fingerprint_plan(plan)
      require "digest"
      require "json"
      normalized = plan.steps.map do |s|
        [s["action"], s["path"], s["command"], Array(s["depends_on"]).map(&:to_i)]
      end
      Digest::SHA256.hexdigest(JSON.generate(normalized))
    end

    def plan_payload(plan)
      {
        "plan_id" => plan.plan_id,
        "goal" => plan.goal,
        "assumptions" => Array(plan.assumptions),
        "steps" => Array(plan.steps),
        "success_criteria" => Array(plan.success_criteria),
        "rollback_strategy" => plan.rollback_strategy,
        "confidence" => plan.confidence
      }
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

    def with_spinner(label, &)
      if ui&.respond_to?(:spinner)
        ui.spinner(label).run(&)
      else
        yield
      end
    end

    def question_about_repo?(task)
      text = task.to_s.strip.downcase
      repo_keywords = %w[repo repository project codebase codebase this repo this repository this project
                         directory structure file structure folder structure project structure]
      repo_keywords.any? { |keyword| text.include?(keyword) }
    end

    def question_about_directory_structure?(task)
      text = task.to_s.strip.downcase
      structure_keywords = %w[directory structure file structure folder structure project structure
                              directory tree file tree folder tree directory layout file layout]
      structure_keywords.any? { |keyword| text.include?(keyword) }
    end

    def question_requires_command?(task)
      text = task.to_s.strip.downcase
      # Detect questions that require running commands to answer
      command_indicators = [
        # Linting/formatting checks
        /\b(rubocop|ruby.?lint|style|offenses?|violations?)\b/i,
        # Test/quality checks
        /\b(test|spec|rspec|jest|coverage|quality|pass|fail)\b/i,
        # Build/compile checks
        /\b(build|compile|make|bundle|install)\b/i,
        # Status checks that need commands
        /\b(is|are|does|do|can|will)\s+(this|the|it)\s+(.*?)\s+(free|clean|pass|fail|working|broken)/i,
        # Direct command requests
        /\brun\s+(rubocop|test|spec|rspec|bundle|make)/i
      ]
      command_indicators.any? { |pattern| text.match?(pattern) }
    end

    def get_directory_structure(max_depth: 3)
      return "" unless context.repo_path && Dir.exist?(context.repo_path)

      build_tree(context.repo_path, "", max_depth: max_depth)
    end

    def build_tree(dir_path, prefix, max_depth:, current_depth: 0)
      return "" if current_depth >= max_depth

      entries = Dir.entries(dir_path)
                   .reject { |e| e.start_with?(".") }
                   .reject { |e| ["node_modules", ".git", ".devagent"].include?(e) }
                   .sort

      return "" if entries.empty?

      result = []
      entries.each_with_index do |entry, index|
        full_path = File.join(dir_path, entry)
        is_last = index == entries.size - 1
        current_prefix = is_last ? "└── " : "├── "
        result << "#{prefix}#{current_prefix}#{entry}"

        next unless File.directory?(full_path)

        next_prefix = prefix + (is_last ? "    " : "│   ")
        subtree = build_tree(full_path, next_prefix, max_depth: max_depth, current_depth: current_depth + 1)
        result << subtree unless subtree.empty?
      end

      result.join("\n")
    end
  end
end
