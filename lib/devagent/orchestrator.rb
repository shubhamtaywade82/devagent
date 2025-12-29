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
require "shellwords"

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

      # Security: Handle "list all files" requests BEFORE intent classification
      # This prevents misclassified intents from bypassing the security check
      rejection_result = should_reject_file_listing_request?(task)
      if rejection_result == true
        requested_path = extract_path_from_listing_request(task)

        # If no path specified (list all files), show clarification but also list allowed directories
        if requested_path.nil?
          unless quiet?
            streamer.say("Clarification needed: Please specify a path. Listing all files in the repository is not allowed for security reasons.", level: :warn)
            streamer.say("Showing files from allowed directories only:")
          end
          # List files from all allowed directories
          return answer_with_allowed_directories(task)
        else
          # Path specified but not allowed
          unless quiet?
            streamer.say("Access denied: The path '#{requested_path}' is not in the allowlist. Please specify a path that is allowed in your configuration.", level: :warn)
          end
          return
        end
      end

      intent = with_spinner("Classifying") { IntentClassifier.new(context).classify(task) }
      state.intent = intent["intent"]
      state.intent_confidence = intent["confidence"].to_f

      # Override classification for explicit modification requests
      # "modify X", "improve X", "refactor X" with file paths should be CODE_EDIT
      if %w[EXPLANATION GENERAL].include?(state.intent)
        task_lower = task.to_s.downcase
        has_file_path = task_lower.match?(/\b([a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json))\b/i)
        is_modify_request = task_lower.match?(/\b(modify|improve|refactor|enhance|update|change)\s+.*\b(to|it|this)\b/i) ||
                            task_lower.match?(/\b(modify|improve|refactor|enhance|update|change)\s+[a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json)\b/i)

        if has_file_path && is_modify_request
          state.intent = "CODE_EDIT"
          state.intent_confidence = [state.intent_confidence, 0.8].max
          context.tracer.event("intent_override", original: intent["intent"], new: "CODE_EDIT", reason: "modify request with file path")
        end
      end

      context.tracer.event("intent", intent: state.intent, confidence: state.intent_confidence)

      if %w[EXPLANATION GENERAL].include?(state.intent)

        # Check if the question requires running a command (e.g., "is this rubocop offenses free?")
        if question_requires_command?(task)
          # Allow EXPLANATION questions that need commands to go through planning
          # This enables run_command to be used for checking tools like rubocop, tests, etc.
        elsif question_needs_file_access?(task)
          # Allow EXPLANATION questions that might need file access (e.g., "what is this repository about?")
          # to go through planning so the LLM can intelligently decide which files to read based on the question
          # and repository context (works for any project type: Rails, Node.js, Python, etc.)
        else
          # Simple conceptual questions that don't need tools - answer directly with indexing if repo-related
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
          visible_tools = if context.tool_registry.respond_to?(:visible_tools_for_phase)
                            context.tool_registry.visible_tools_for_phase(:planning)
                          elsif context.tool_registry.respond_to?(:tools_for_phase)
                            context.tool_registry.tools_for_phase(:planning).values
                          else
                            context.tool_registry.tools.values
                          end
          unless context.config.dig("auto", "enable_git_tools") == true
            visible_tools = Array(visible_tools).reject { |t| t.respond_to?(:category) && t.category.to_s == "git" }
          end

          plan = with_spinner("Planning") do
            planner.plan(task, controller_feedback: controller_feedback(state), visible_tools: visible_tools)
          end

          state.plan = plan
          context.tracer.event("plan", plan_id: plan.plan_id, goal: plan.goal, confidence: plan.confidence,
                                       steps: plan.steps)
          streamer.say("Plan: #{plan.goal} (#{(plan.confidence * 100).round}%)") if plan.goal && !quiet?

          # Check if we should use fallback for command-checking questions with low confidence
          if question_requires_command?(task) && plan.confidence.to_f < 0.3
            unless quiet?
              streamer.say("Planning generated low confidence. Using fallback plan for command execution...",
                           level: :warn)
            end
            minimal_plan = create_minimal_command_plan(task)
            if minimal_plan
              state.plan = minimal_plan
              state.phase = :execution
              next
            end
          end

          # Check if we should fallback for EXPLANATION questions that need file access
          # If planning fails, fall back to indexing + direct answer (simpler approach)
          if question_needs_file_access?(task) && %w[EXPLANATION GENERAL].include?(state.intent)
            if plan.confidence.to_f < 0.3 || plan.steps.empty?
              unless quiet?
                streamer.say("Planning generated low confidence for explanation question. Falling back to indexing...",
                             level: :warn)
              end
              use_repo_context = question_about_repo?(task)
              return answer_unactionable(task, state.intent_confidence, use_repo_context: use_repo_context)
            end
          end

          # Check if we should use fallback for CODE_EDIT tasks with low confidence
          # Do this BEFORE validation to avoid unnecessary validation errors
          if state.intent == "CODE_EDIT" && (plan.confidence.to_f < 0.3 || plan.steps.empty?)
            unless quiet?
              streamer.say("Planning generated low confidence for code edit. Attempting to create minimal plan...",
                           level: :warn)
            end
            # Check if this is a file creation request
            is_create_request = task.to_s.downcase.match?(/\b(create|new|add)\s+(?:a\s+)?(?:new\s+)?file\b/i)
            minimal_plan = if is_create_request
                             create_minimal_create_plan(task)
                           else
                             create_minimal_edit_plan(task)
                           end
            if minimal_plan
              state.plan = minimal_plan
              state.phase = :execution
              next
            else
              # If minimal plan creation failed, provide helpful error message
              if is_create_request
                # Try to extract the path to give a specific error
                file_path_match = task.to_s.match(/\b(?:create|new|add)\s+(?:a\s+)?(?:new\s+)?file\s+([a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json))\b/i)
                file_path = file_path_match ? file_path_match[1] : nil
                unless file_path
                  any_match = task.to_s.match(/\b([a-zA-Z0-9_\-\.\/]+\/(?:[a-zA-Z0-9_\-\.\/]+\/)*[a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json))\b/i)
                  file_path = any_match[1] if any_match
                end
                if file_path && !context.tool_bus.safety.allowed?(file_path)
                  unless quiet?
                    streamer.say("Cannot create file: '#{file_path}' is in the denylist or not in the allowlist.", level: :warn)
                    streamer.say("Please use an allowed path (e.g., 'lib/hello.rb' instead of 'tmp/hello.rb').", level: :info)
                  end
                  return
                end
              end
            end
          end

          begin
            validate_plan!(state, plan, visible_tools: visible_tools)
          rescue StandardError => e
            streamer.say("PLAN_REJECTED: #{e.message}", level: :warn) unless quiet?
            # If validation fails for a command-checking question, try fallback
            if question_requires_command?(task)
              streamer.say("Plan validation failed. Trying fallback plan...", level: :warn) unless quiet?
              minimal_plan = create_minimal_command_plan(task)
              if minimal_plan
                state.plan = minimal_plan
                state.phase = :execution
                next
              end
            end
            # If validation fails for an EXPLANATION question that needs file access, fall back to indexing
            if question_needs_file_access?(task) && %w[EXPLANATION GENERAL].include?(state.intent)
              streamer.say("Plan validation failed. Falling back to indexing for explanation...", level: :warn) unless quiet?
              use_repo_context = question_about_repo?(task)
              return answer_unactionable(task, state.intent_confidence, use_repo_context: use_repo_context)
            end
            # If validation fails for other reasons (not confidence), we've already tried minimal plan above
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
        when :done
          # Generate answer based on observations and command output
          generate_answer(task, state)
          break
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
        error_msg = e.message
        streamer.say("Step #{step["step_id"]} failed: #{error_msg}", level: :error)
        state.record_error(signature: "step_failed:#{step["step_id"]}", message: error_msg)
        state.step_results[step["step_id"]] = { "success" => false, "error" => error_msg }
        state.record_observation({ "type" => "STEP_FAILED", "step_id" => step["step_id"], "status" => "FAIL",
                                   "error" => error_msg })
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
      content = step["content"]

      case action
      when "fs.read", "fs_read"
        tool_invoke_with_policy(state, "fs.read", "path" => path)
      when "fs.create"
        raise Error, "path required" if path.to_s.empty?
        raise Error, "file already exists: #{path}" if File.exist?(File.join(context.repo_path, path.to_s))

        raise Error, "content required" if content.to_s.empty?

        # Deterministic add-file diff generation (do not rely on model formatting).
        diff = build_add_file_diff(path: path.to_s, content: content.to_s)

        tool_invoke_with_policy(state, "fs.write_diff", "path" => path.to_s, "diff" => diff)
      when "fs.write", "fs_write"
        # diff-first write: read must have happened, then generate diff, then apply diff.
        raise Error, "path required" if path.to_s.empty?

        ensure_read_same_path!(state, path)
        original = context.tool_bus.read_file("path" => path.to_s).fetch("content")
        diff = DiffGenerator.new(context).generate(
          path: path.to_s,
          original: original,
          goal: plan.goal.to_s,
          reason: step["reason"].to_s,
          file_exists: true
        )
        tool_invoke_with_policy(state, "fs.write_diff", "path" => path.to_s, "diff" => diff)
      when "fs.delete", "fs_delete"
        raise Error, "path required" if path.to_s.empty?

        ensure_read_same_path!(state, path)
        tool_invoke_with_policy(state, "fs.delete", "path" => path.to_s)
      when "exec.run", "run_command", "run_tests"
        # Back-compat: string commands are parsed into program+args.
        # exec.run itself only accepts structured invocations.
        cmd = command.to_s
        cmd = "bundle exec rspec" if action == "run_tests" && cmd.strip.empty?
        tokens = Shellwords.split(cmd)
        raise Error, "command required" if tokens.empty?

        tool_invoke_with_policy(
          state,
          "exec.run",
          "program" => tokens.first,
          "args" => tokens.drop(1),
          "accepted_exit_codes" => step["accepted_exit_codes"],
          "allow_failure" => step["allow_failure"]
        )
      when "diagnostics.error_summary"
        tool_invoke_with_policy(state, "diagnostics.error_summary", "stderr" => command.to_s)
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

      success =
        if tool_name == "exec.run"
          exit_code = result.is_a?(Hash) ? result["exit_code"].to_i : 0
          accepted = Array(args["accepted_exit_codes"]).map(&:to_i)
          allow_failure = args["allow_failure"] == true
          exit_code == 0 || allow_failure || accepted.include?(exit_code)
        else
          true
        end

      { "success" => success, "artifact" => result }
    end

    def record_artifacts(state, tool_name, args, result)
      case tool_name
      when "fs.read"
        state.record_file_read(args["path"], meta: file_meta(args["path"]))
      when "fs.write_diff"
        state.record_file_written(args["path"])
      when "exec.run"
        # Reconstruct command string from program + args for logging
        program = args["program"].to_s
        cmd_args = Array(args["args"]).map(&:to_s)
        command_str = [program, *cmd_args].join(" ")
        state.record_command(command_str)
        # For status-checking commands (like rubocop, tests), include more output lines
        # to capture all the details (offenses, test results, etc.)
        is_status_check = command_str.match?(/\b(rubocop|rspec|test|spec|lint)\b/i)
        output_lines = is_status_check ? 100 : 20
        state.record_observation({
                                   "type" => "COMMAND_EXECUTED",
                                   "command" => command_str,
                                   "stdout" => truncate_output(result["stdout"].to_s, lines: output_lines),
                                   "stderr" => truncate_output(result["stderr"].to_s, lines: output_lines),
                                   "exit_code" => result["exit_code"].to_i
                                 })
      when "diagnostics.error_summary"
        state.record_observation({ "type" => "ERROR_SUMMARY", "root_cause" => result["root_cause"],
                                   "confidence" => result["confidence"] })
      end
    end

    def ensure_read_same_path!(state, path)
      p = path.to_s
      raise Error, "fs.write requires prior fs.read of #{p}" unless state.artifacts[:files_read].include?(p)

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

    # List files from all allowed directories when user requests "list all files"
    def answer_with_allowed_directories(_task)
      allowlist = Array(context.config.dig("auto", "allowlist"))

      # Extract directory paths from allowlist patterns (e.g., "lib/**" -> "lib")
      # Skip patterns like "README*" that are file patterns, not directories
      allowed_dirs = allowlist
        .map { |pattern| pattern.gsub(/\*\*?$/, "").chomp("/") }
        .reject { |dir| dir.empty? || dir.include?("*") || dir.include?("?") }
        .select { |dir|
          full_path = File.join(context.repo_path, dir)
          # Check if it's a directory and if files in it would be allowed
          Dir.exist?(full_path) && context.tool_bus.safety.allowed?("#{dir}/test.rb")
        }
        .sort

      if allowed_dirs.empty?
        streamer.say("No allowed directories found in the repository.", markdown: true)
        return
      end

      # Build directory structure for each allowed directory
      structures = allowed_dirs.map do |dir|
        structure = get_directory_structure(path: dir, max_depth: 2)
        structure.empty? ? nil : "#{dir}/\n#{structure}"
      end.compact

      if structures.empty?
        streamer.say("No files found in allowed directories.", markdown: true)
        return
      end

      # Show the directory structures
      streamer.say("Files from allowed directories:\n\n#{structures.join("\n\n")}", markdown: true)
    end

    # When planning yields no actions, answer the user's question directly using
    # the developer model and light repository context.
    def answer_unactionable(task, confidence, use_repo_context: true)
      # Security: Don't process "list all files" requests - these should have been rejected earlier
      if should_reject_file_listing_request?(task)
        unless quiet?
          streamer.say("I cannot list all files in the repository for security reasons. Please specify a specific path or directory you'd like to explore.")
        end
        return
      end

      streamer.say("Answer:") unless quiet?
      prompt = build_answer_prompt(task, use_repo_context: use_repo_context)

      # If prompt is empty (e.g., rejected request), don't query the LLM
      return if prompt.empty?

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

    # Generate answer when we have command output from observations
    def generate_answer(task, state)
      streamer.say("Answer:") unless quiet?

      # Build prompt with command output from observations
      prompt = build_answer_prompt_with_observations(task, state)

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
      # Security: Don't allow "list all files" requests - these should have been rejected earlier
      # But add a safety check here too to prevent directory traversal
      return "" if should_reject_file_listing_request?(task)

      # For repository description questions, try to read README files directly
      # This ensures we get documentation even if semantic search doesn't find it
      readme_content = if question_needs_file_access?(task) && question_about_repo?(task)
                         read_readme_files_directly
                       else
                         ""
                       end

      retrieved = if use_repo_context
                    # Reduce to 4 snippets to avoid prompt truncation
                    safe_index_retrieve(task, limit: 4).map do |snippet|
                      # Truncate long snippets
                      text = snippet["text"].to_s
                      text = text.length > 500 ? "#{text[0..500]}... (truncated)" : text
                      "#{snippet["path"]}:\n#{text}\n---"
                    end.join("\n")
                  else
                    ""
                  end

      # Include directory structure if the question is about directory structure
      # But NOT for "list all files" requests (security)
      # If a specific allowed path is mentioned, list only that path
      dir_structure = if question_about_directory_structure?(task) && !should_reject_file_listing_request?(task)
                        requested_path = extract_path_from_listing_request(task)
                        if requested_path
                          # List files from the specific allowed path
                          full_path = File.join(context.repo_path, requested_path)
                          if Dir.exist?(full_path) && context.tool_bus.safety.allowed?(requested_path)
                            get_directory_structure(path: requested_path)
                          else
                            ""
                          end
                        else
                          # General directory structure question (not a listing request)
                          get_directory_structure
                        end
                      else
                        ""
                      end

      # Reduce history to 3 turns to save tokens
      history = safe_session_history(limit: 3).map do |turn|
        content = turn["content"].to_s
        # Truncate long history entries
        content = content.length > 200 ? "#{content[0..200]}... (truncated)" : content
        "#{turn["role"]}: #{content}"
      end.join("\n")

      <<~PROMPT
        You are a concise, helpful developer assistant.
        If the question relates to this repository, use the context below; otherwise answer generally.

        Recent conversation:
        #{history}

        #{"Directory structure:\n#{dir_structure}\n\n" unless dir_structure.empty?}#{"Documentation:\n#{readme_content}\n\n" unless readme_content.empty?}Repository context:
        #{retrieved.empty? ? "(none)" : retrieved}

        Question:
        #{task}
      PROMPT
    end

    def build_answer_prompt_with_observations(task, state)
      # Extract command output from observations
      command_observations = state.observations.select { |o| o["type"] == "COMMAND_EXECUTED" }
      command_output = ""
      command_observations.each do |obs|
        command_output += "Command: #{obs["command"]}\n"
        command_output += "Exit code: #{obs["exit_code"]}\n"
        command_output += "STDOUT:\n#{obs["stdout"]}\n" if obs["stdout"] && !obs["stdout"].empty?
        command_output += "STDERR:\n#{obs["stderr"]}\n" if obs["stderr"] && !obs["stderr"].empty?
        command_output += "\n---\n"
      end

      # Reduce history to 3 turns to save tokens
      history = safe_session_history(limit: 3).map do |turn|
        content = turn["content"].to_s
        # Truncate long history entries
        content = content.length > 200 ? "#{content[0..200]}... (truncated)" : content
        "#{turn["role"]}: #{content}"
      end.join("\n")

      <<~PROMPT
        You are a concise, helpful developer assistant.
        Answer the user's question based on the command output provided below.
        Include specific details from the command output in your answer (file names, line numbers, error messages, warnings, etc.).

        Recent conversation:
        #{history}

        Command execution results:
        #{command_output.empty? ? "(no command output)" : command_output}

        Question:
        #{task}

        Provide a detailed answer that includes all relevant information from the command output above.
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

      # Include help output if it was checked - this is critical for command execution
      help_observations = recent.select { |o| o["type"] == "COMMAND_HELP_CHECKED" }
      help_observations.each do |obs|
        parts << "Command help checked for: #{obs["command"]}"
        parts << "Help output: #{obs["help_output"]}" if obs["help_output"]
      end

      # Include command execution results
      command_observations = recent.select { |o| o["type"] == "COMMAND_EXECUTED" }
      command_observations.each do |obs|
        parts << "Command executed: #{obs["command"]}"
        parts << "Exit code: #{obs["exit_code"]}"
        parts << "STDOUT (last 20 lines):\n#{obs["stdout"]}" if obs["stdout"] && !obs["stdout"].empty?
        parts << "STDERR (last 20 lines):\n#{obs["stderr"]}" if obs["stderr"] && !obs["stderr"].empty?
      end

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
      # Special handling for command-checking questions: if we have command output, proceed to answer
      if question_requires_command?(task)
        command_observations = state.observations.select { |o| o["type"] == "COMMAND_EXECUTED" }
        if command_observations.any?
          # We have command output, generate answer directly
          state.confidence = 0.8
          generate_answer(task, state)
          state.phase = :halted # Set to halted to exit the loop
          return
        end
      end

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
      # For command-only plans (checking tools like rubocop), allow lower confidence
      # since these are straightforward tasks
      has_commands = plan.steps.any? { |s| %w[exec.run run_command run_tests].include?(s["action"].to_s) }
      # For read-only plans (EXPLANATION questions that just need to read files), also allow lower confidence
      has_only_reads = plan.steps.all? { |s| %w[fs.read fs_read].include?(s["action"].to_s) } && !plan.steps.empty?
      min_confidence = if has_commands || has_only_reads
                         0.3
                       else
                         0.5
                       end
      raise Error, "plan confidence too low" if plan.confidence.to_f < min_confidence

      allowed = Array(visible_tools).map(&:name)
      # Plan-level allowlist must be LLM-visible tools only (never allow internal execution tools).
      allowed_aliases = %w[fs_write fs_read fs_delete run_command run_tests].freeze
      allowed_names = (allowed + allowed_aliases).uniq

      step_actions = plan.steps.map { |s| s["action"].to_s }
      # Back-compat aliases are allowed, but normalized during execution.
      unknown = step_actions.reject do |a|
        allowed_names.include?(a)
      end
      raise Error, "plan uses unknown tools: #{unknown.uniq.join(", ")}" unless unknown.empty?

      # Read scope limiter: first cycle may read at most one file.
      # Exception: if plan includes commands, relax the restriction
      # This allows plans that run tools like rubocop even if they read some files first
      has_commands = plan.steps.any? { |s| %w[exec.run run_command run_tests].include?(s["action"].to_s) }
      if state.cycle.to_i == 0 && !has_commands
        reads = plan.steps.count { |s| %w[fs.read fs_read].include?(s["action"].to_s) }
        raise Error, "too many reads in first plan" if reads > 1
      end

      # Enforce: every fs.write depends on a prior fs.read of the same path.
      reads = {}
      plan.steps.each do |s|
        reads[s["step_id"]] = s["path"].to_s if %w[fs.read fs_read].include?(s["action"].to_s)
      end

      # Enforce: fs.read must only target existing files.
      # For new files, the planner must use fs.create.
      plan.steps.each do |s|
        next unless %w[fs.read fs_read].include?(s["action"].to_s)

        path = s["path"].to_s
        raise Error, "fs.read path required" if path.empty?

        full = File.join(context.repo_path.to_s, path)
        next if File.exist?(full)

        state.record_observation({ "type" => "FILE_MISSING", "path" => path })
        raise Error, "fs.read on non-existent file (use fs.create for new files): #{path}"
      end

      # Enforce: fs.create must only target non-existent files, and should not require dependencies.
      plan.steps.each do |s|
        next unless %w[fs.create fs_create].include?(s["action"].to_s)

        path = s["path"].to_s
        raise Error, "fs.create path required" if path.empty?

        full = File.join(context.repo_path.to_s, path)
        raise Error, "fs.create target already exists: #{path}" if File.exist?(full)
      end

      plan.steps.each do |s|
        next unless %w[fs.write fs_write].include?(s["action"].to_s)

        path = s["path"].to_s
        raise Error, "fs.write path required" if path.empty?

        full = File.join(context.repo_path.to_s, path)
        raise Error, "fs.write cannot create new files; use fs.create: #{path}" unless File.exist?(full)

        deps = Array(s["depends_on"]).map(&:to_i)
        dep_paths = deps.filter_map { |id| reads[id] }
        raise Error, "fs.write must depend_on prior fs.read of same path (#{path})" unless dep_paths.include?(path)
      end

      # Only fingerprint AFTER all validation checks pass.
      fp = fingerprint_plan(plan)
      raise Error, "plan repeated without progress" if state.plan_fingerprints.include?(fp)
      state.plan_fingerprints << fp
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

    def question_needs_file_access?(task)
      text = task.to_s.strip.downcase
      original_text = task.to_s.strip

      # Security: Don't allow "list all files" requests to go through file access path
      return false if should_reject_file_listing_request?(task)

      # Questions that might need reading files (documentation, source files, config files, etc.)
      # The LLM will decide which specific files to read based on the question and repository context
      file_access_indicators = [
        "what is this", "what is the", "what's this", "what's the",
        "about", "description", "purpose", "what does", "what do",
        "explain this repo", "explain this repository", "explain this project",
        "read", "show me", "what files", "what's in"
        # Note: "list files" removed - use should_reject_file_listing_request? instead
      ]

      # Questions about specific classes/components in the repository need file access
      # e.g., "explain how ToolRegistry works" - needs to read the actual code
      code_component_indicators = [
        "explain how", "how does", "how do", "how is", "how are",
        "what is", "what does", "what do"
      ]
      mentions_code_component = code_component_indicators.any? { |keyword| text.include?(keyword) } &&
                                (text.match?(/\b(class|module|function|method|component|system|registry|tool|agent|planner|orchestrator)\b/i) ||
                                 original_text.match?(/\b[A-Z][a-zA-Z]+\b/)) # Capitalized words likely refer to classes - check original text

      general_file_access = file_access_indicators.any? { |keyword| text.include?(keyword) } &&
                            question_about_repo?(task)

      general_file_access || mentions_code_component
    end

    def extract_path_from_listing_request(task)
      original_text = task.to_s.strip

      # First check if it's a generic "this repository/repo/project/codebase" request
      # These should be rejected - they mean "all files"
      generic_pattern = /\b(in|of|from)\s+(this\s+)?(repo|repository|project|codebase)\b/i
      return nil if original_text.match?(generic_pattern)

      # Look for path-like patterns: "in lib/", "in docs/", "in app/", etc.
      # But exclude "this" followed by repo/repository/project/codebase
      path_pattern = /\b(in|of|from)\s+([a-zA-Z0-9_\-\.\/]+(?:\/[a-zA-Z0-9_\-\.\/]*)?)\b/i
      path_match = original_text.match(path_pattern)
      return nil if path_match.nil?

      requested_path = path_match[2].strip
      # Double-check: if path is just "this" or starts with "this ", it's likely "this repository"
      return nil if requested_path == "this" || requested_path.start_with?("this ")

      # If path is "repo/repository/project/codebase" (without "this"), also reject
      return nil if requested_path.match?(/^(repo|repository|project|codebase)$/i)

      requested_path.chomp("/")
    end

    def should_reject_file_listing_request?(task)
      text = task.to_s.strip.downcase

      # Check if this is a file listing request
      is_listing_request = text.match?(/\b(list|show)\s+(all\s+)?files?\s+(in|of|from)\b/i)
      return false unless is_listing_request

      # Extract the path
      requested_path = extract_path_from_listing_request(task)

      # If no specific path mentioned, reject it
      return true if requested_path.nil?

      # Check if the path is allowed using Safety
      safety = context.tool_bus.safety

      # Normalize the path: ensure it doesn't have a trailing slash for consistency
      normalized_path = requested_path.chomp("/")

      # Test with various file paths in that directory to see if the directory is allowed
      # The allowlist uses glob patterns like "docs/**" or "lib/**", which match files under
      # that directory, not the directory name itself. So we test with file paths.
      test_paths = [
        "#{normalized_path}/README.md", # Common file
        "#{normalized_path}/test.rb",    # Example Ruby file
        "#{normalized_path}/test.txt",   # Example text file
        "#{normalized_path}/index.js"    # Example JS file
      ]

      # If any test path is allowed, permit the listing (return false = don't reject)
      # Note: We don't test the directory name itself because glob patterns like "docs/**"
      # match files under docs/, not "docs" itself
      is_allowed = test_paths.any? { |test_path| safety.allowed?(test_path) }

      # Return true to reject if NOT allowed, false to allow if it IS allowed
      !is_allowed
    rescue StandardError
      # If anything goes wrong, default to rejecting for security
      true
    end

    def question_about_directory_structure?(task)
      text = task.to_s.strip.downcase
      # Security: Don't allow "list all files" - this should be rejected or require clarification
      return false if should_reject_file_listing_request?(task)

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

    def create_minimal_command_plan(task)
      # Create a simple plan for command-checking questions when planner fails
      text = task.to_s.strip.downcase

      # Determine which command to run
      base_command = if text.include?("rubocop")
                       "rubocop"
                     elsif text.match?(/\b(test|spec|rspec)\b/i)
                       "rspec"
                     else
                       nil
                     end

      return nil unless base_command

      # For status-checking questions (e.g., "is it free?", "does it pass?"),
      # accept non-zero exit codes since we're checking status, not requiring success
      is_status_check = text.match?(/\b(is|are|does|do|can|will)\s+(this|the|it|app|code)\s+/i) ||
                        text.include?("free") || text.include?("offenses") || text.include?("violations")

      step = {
        "step_id" => 1,
        "action" => "exec.run",
        "command" => base_command == "rspec" ? "bundle exec rspec" : "bundle exec #{base_command}",
        "path" => nil,
        "reason" => "Run command to check status",
        "depends_on" => []
      }

      # For status checks, accept exit codes 0 and 1 (success and found issues)
      # This prevents the step from being marked as "failed" when we successfully got the status
      if is_status_check
        step["accepted_exit_codes"] = [0, 1]
      end

      steps = [step]

      Plan.new(
        plan_id: "minimal_#{Time.now.to_i}",
        goal: task,
        assumptions: ["Using minimal plan due to planner failure"],
        steps: steps,
        success_criteria: ["Command executed successfully"],
        rollback_strategy: "None needed for read-only command",
        confidence: 0.6,
        summary: task,
        actions: []
      )
    end

    def create_minimal_edit_plan(task)
      # Create a simple plan for code editing tasks when planner fails
      # This handles simple cases like "add a comment at the top of file.rb"

      # Extract file path from common patterns
      # Patterns: "add X to file.rb", "add X at the top of file.rb", "add X in file.rb", "modify lib/file.rb"
      file_path_match = task.to_s.match(/\b(?:at\s+the\s+top\s+of|in|to|at|modify|update|change|edit|refactor|improve)\s+([a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json))\b/i)
      file_path = file_path_match ? file_path_match[1] : nil

      # If no file path found, try to extract from anywhere in the task
      unless file_path
        # Look for file paths with common extensions anywhere in the text
        # Matches patterns like "lib/file.rb", "src/file.js", etc.
        any_match = task.to_s.match(/\b([a-zA-Z0-9_\-\.\/]+\/(?:[a-zA-Z0-9_\-\.\/]+\/)*[a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json))\b/i)
        file_path = any_match[1] if any_match
      end

      # If still no match, try simple filename patterns
      unless file_path
        simple_match = task.to_s.match(/\b([a-zA-Z0-9_\-\.\/]+\.[a-zA-Z0-9]+)\b/i)
        file_path = simple_match[1] if simple_match
      end

      unless file_path
        context.tracer.event("minimal_edit_plan_failed", reason: "Could not extract file path from task", task: task.to_s) if context.respond_to?(:tracer)
        return nil
      end

      # Validate the file path is allowed
      unless context.tool_bus.safety.allowed?(file_path)
        context.tracer.event("minimal_edit_plan_failed", reason: "File path not in allowlist", path: file_path) if context.respond_to?(:tracer)
        return nil
      end

      # Create a simple plan: read the file, then write it with modifications
      steps = [
        {
          "step_id" => 1,
          "action" => "fs.read",
          "path" => file_path,
          "reason" => "Read file to understand current content",
          "depends_on" => []
        },
        {
          "step_id" => 2,
          "action" => "fs.write",
          "path" => file_path,
          "reason" => task.to_s.strip,
          "depends_on" => [1]
        }
      ]

      Plan.new(
        plan_id: "minimal_edit_#{Time.now.to_i}",
        goal: task,
        assumptions: ["Using minimal plan: read file then apply requested changes"],
        steps: steps,
        success_criteria: ["File read and modified successfully"],
        confidence: 0.8
      )
    end

    def create_minimal_create_plan(task)
      # Create a simple plan for file creation tasks when planner fails
      # This handles cases like "create a new file lib/hello.rb that prints hello"

      # Extract file path - look for patterns like "create file path/to/file.rb"
      file_path_match = task.to_s.match(/\b(?:create|new|add)\s+(?:a\s+)?(?:new\s+)?file\s+([a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json))\b/i)
      file_path = file_path_match ? file_path_match[1] : nil

      # If no match, try to find file path anywhere in the text
      unless file_path
        any_match = task.to_s.match(/\b([a-zA-Z0-9_\-\.\/]+\/(?:[a-zA-Z0-9_\-\.\/]+\/)*[a-zA-Z0-9_\-\.\/]+\.(?:rb|js|ts|py|java|go|rs|php|tsx|jsx|md|txt|yml|yaml|json))\b/i)
        file_path = any_match[1] if any_match
      end

      # If still no match, try simple filename
      unless file_path
        simple_match = task.to_s.match(/\b([a-zA-Z0-9_\-\.\/]+\.[a-zA-Z0-9]+)\b/i)
        file_path = simple_match[1] if simple_match
      end

      unless file_path
        context.tracer.event("minimal_create_plan_failed", reason: "Could not extract file path from task", task: task.to_s) if context.respond_to?(:tracer)
        return nil
      end

      # Validate the file path is allowed
      unless context.tool_bus.safety.allowed?(file_path)
        context.tracer.event("minimal_create_plan_failed", reason: "File path not allowed (may be in denylist)", path: file_path) if context.respond_to?(:tracer)
        return nil
      end

      # Generate file content based on the task description
      # Extract what the file should do from the task
      content_description = task.to_s
      # Remove the "create file X" part to get the content description
      content_description = content_description.gsub(/\b(?:create|new|add)\s+(?:a\s+)?(?:new\s+)?file\s+[^\s]+\s*(?:that|which|to)?\s*/i, "").strip
      # If nothing left, use the full task as description
      content_description = task.to_s if content_description.empty?

      # Generate content using LLM
      file_content = generate_file_content(file_path, content_description, task)

      # Create a simple plan: create the file with generated content
      steps = [
        {
          "step_id" => 1,
          "action" => "fs.create",
          "path" => file_path,
          "content" => file_content,
          "reason" => task.to_s.strip,
          "depends_on" => []
        }
      ]

      Plan.new(
        plan_id: "minimal_create_#{Time.now.to_i}",
        goal: task,
        assumptions: ["Using minimal plan: create new file with content based on task description"],
        steps: steps,
        success_criteria: ["File created successfully"],
        confidence: 0.8
      )
    end

    def generate_file_content(file_path, content_description, full_task)
      # Generate file content using the developer model
      # Determine file type from extension
      ext = File.extname(file_path).downcase
      language = case ext
                 when ".rb"
                   "Ruby"
                 when ".js", ".jsx"
                   "JavaScript"
                 when ".ts", ".tsx"
                   "TypeScript"
                 when ".py"
                   "Python"
                 when ".java"
                   "Java"
                 when ".go"
                   "Go"
                 when ".rs"
                   "Rust"
                 when ".php"
                   "PHP"
                 when ".md"
                   "Markdown"
                 when ".txt"
                   "Plain text"
                 when ".yml", ".yaml"
                   "YAML"
                 when ".json"
                   "JSON"
                 else
                   "code"
                 end

      prompt = <<~PROMPT
        Create a new #{language} file at #{file_path}.

        Requirements:
        #{content_description}

        Full task: #{full_task}

        Generate the complete file content. Return ONLY the file content, no explanations, no markdown code blocks, just the raw file content.
      PROMPT

      begin
        content = context.query(
          role: :developer,
          prompt: prompt,
          stream: false,
          params: { temperature: 0.2 }
        ).to_s.strip

        # Remove markdown code blocks if present
        content = content.gsub(/^```(?:#{language.downcase}|ruby|javascript|typescript|python|java|go|rust|php|markdown|yaml|json|text)?\s*\n/, "")
                        .gsub(/\n```\s*$/, "")
                        .strip

        # Ensure content is not empty
        return generate_fallback_content(file_path, content_description) if content.empty?

        content
      rescue StandardError => e
        context.tracer.event("content_generation_failed", message: e.message, path: file_path) if context.respond_to?(:tracer)
        # Fallback: generate simple content based on description
        generate_fallback_content(file_path, content_description)
      end
    end

    def generate_fallback_content(file_path, description)
      ext = File.extname(file_path).downcase
      case ext
      when ".rb"
        if description.downcase.include?("print") || description.downcase.include?("hello")
          "puts 'hello'\n"
        else
          "# #{description}\n\n"
        end
      when ".js", ".jsx"
        "console.log('hello');\n"
      when ".py"
        "print('hello')\n"
      when ".md"
        "# #{description}\n\n"
      when ".txt"
        "#{description}\n"
      else
        "# #{description}\n"
      end
    end

    def get_directory_structure(path: nil, max_depth: 3)
      return "" unless context.repo_path && Dir.exist?(context.repo_path)

      # If a specific path is requested, use that; otherwise use repo root
      target_path = if path
                      full_path = File.join(context.repo_path, path)
                      # Validate the path is allowed and exists
                      # Check with a test file path since glob patterns like "lib/**" match files, not directories
                      return "" unless Dir.exist?(full_path)
                      test_file_path = "#{path}/test.rb"
                      return "" unless context.tool_bus.safety.allowed?(test_file_path)
                      full_path
                    else
                      context.repo_path
                    end

      build_tree(target_path, "", max_depth: max_depth)
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

    def truncate_output(output, lines: 20)
      return "" if output.nil? || output.empty?

      output_lines = output.split("\n")
      return output if output_lines.size <= lines

      # Return last N lines with a note
      truncated = output_lines.last(lines).join("\n")
      "#{truncated}\n... (showing last #{lines} of #{output_lines.size} lines)"
    end

    def read_readme_files_directly
      # Try to read common documentation files in order of priority
      # This is a fallback when planning fails or semantic search doesn't find README
      readme_paths = %w[README.md README.txt README README.rst README.markdown]
      readme_content = []

      readme_paths.each do |path|
        full_path = File.join(context.repo_path, path)
        next unless File.exist?(full_path)

        begin
          # Read directly (safe for documentation files in repo root)
          # We bypass tool_bus here because this is a fallback mechanism and README files
          # are generally safe to read
          content = File.read(full_path, encoding: "UTF-8")
          readme_content << "#{path}:\n#{content}\n---" unless content.empty?
          break # Use the first found README file
        rescue StandardError => e
          context.tracer.event("readme_read_failed", path: path, message: e.message) if context.respond_to?(:tracer)
          next
        end
      end

      readme_content.join("\n")
    end

    # Build a minimal unified diff for creating a new file from scratch.
    #
    # This is controller-owned and deterministic; it avoids relying on model-produced diff formatting.
    def build_add_file_diff(path:, content:)
      raise Error, "content required" if content.to_s.empty?

      lines = content.to_s.lines
      raise Error, "content required" if lines.empty?

      hunk_lines = lines.map { |line| "+#{line}" }.join
      hunk_count = lines.size

      <<~DIFF
        --- /dev/null
        +++ b/#{path}
        @@ -0,0 +1,#{hunk_count} @@
        #{hunk_lines}
      DIFF
    end
  end
end
