# frozen_string_literal: true

require "json"
require_relative "../planning_failed"
require_relative "../context"
require_relative "plan"

module Devagent
  module Planning
    class Planner
      MIN_CONFIDENCE = 50

      def initialize(repo_path:, context:)
        @repo_path = repo_path
        @context = context
        # Try to use llama3.1:8b, but fall back to configured planner_model if not available
        @preferred_model = "llama3.1:8b"
        @planner_model = context.config["planner_model"] || "llama3.1:8b"
      end

      def call(user_prompt)
        @user_prompt = user_prompt
        # Check if repo is empty
        is_empty = repo_empty?

        response = query_planner(user_prompt, is_empty)

        plan = parse_plan(response, is_empty)

        unless plan.valid? && plan.confidence >= MIN_CONFIDENCE
          raise PlanningFailed, "Planning confidence too low: #{plan.confidence}% (minimum: #{MIN_CONFIDENCE}%)"
        end

        plan
      end

      private

      attr_reader :repo_path, :context, :planner_model, :preferred_model, :user_prompt

      def repo_empty?
        # Check if repo has any code files (excluding .git, node_modules, etc.)
        allowed_extensions = %w[.rb .js .ts .py .java .go .rs .php .tsx .jsx .md .txt .yml .yaml .json]
        has_files = Dir.glob(File.join(repo_path, "**/*")).any? do |file|
          next false unless File.file?(file)
          next true if file.include?(".git") || file.include?("node_modules")

          ext = File.extname(file)
          allowed_extensions.include?(ext)
        end
        !has_files
      end

      def query_planner(user_prompt, is_empty)
        prompt = build_prompt(user_prompt, is_empty)

        # Try preferred model first, fall back to configured model if it fails
        original_planner_model = context.config["planner_model"]

        # Try preferred model first
        context.config["planner_model"] = preferred_model
        # Clear LLM cache to force new model
        context.llm_cache.delete(:planner) if context.llm_cache

        begin
          context.query(
            role: :planner,
            prompt: prompt,
            stream: false,
            params: { temperature: 0.1 }
          )
        rescue StandardError
          # If preferred model fails, try configured model
          raise unless preferred_model != planner_model

          context.config["planner_model"] = planner_model
          context.llm_cache.delete(:planner) if context.llm_cache
          context.query(
            role: :planner,
            prompt: prompt,
            stream: false,
            params: { temperature: 0.1 }
          )
        ensure
          # Restore original model
          context.config["planner_model"] = original_planner_model
          context.llm_cache.delete(:planner) if context.llm_cache
        end
      end

      def build_prompt(user_prompt, is_empty)
        empty_repo_instruction = if is_empty
                                   "\n\nCRITICAL: Repository is empty. You MUST:\n" \
                                     "- Set confidence >= 70\n" \
                                     "- Include 'BOOTSTRAP_REPO' as the first step in steps array\n"
                                 else
                                   ""
                                 end

        <<~PROMPT
          You are a PLANNING ENGINE.

          You MUST return JSON only with:
          - confidence (0–100 integer)
          - steps (array of step objects, each with: step_id, action, path/command/content as needed, reason, depends_on)
          - blockers (array of strings)

          Rules:
          - Do NOT write code
          - Do NOT suggest implementations
          - Return VALID JSON only - no markdown code blocks, no extra text
          - Each step must have: step_id (integer >= 1), action (string), reason (string), depends_on (array of integers)
          - Actions: fs.read, fs.write, fs.create, fs.delete, exec.run

          Filesystem semantics (CRITICAL):
          - fs.read: ONLY for files that ALREADY EXIST. Never use fs.read on files that don't exist.
          - fs.create: ONLY for creating NEW files that don't exist yet. MUST include 'content' field with the complete file content. NEVER use fs.write after fs.create for the same file - fs.create already includes the content.
          - fs.write: ONLY for editing EXISTING files. Must depend_on a prior fs.read of the same path. NEVER use fs.write on a file that doesn't exist yet - use fs.create instead.
          - fs.delete: ONLY for deleting EXISTING files.
          - CRITICAL: For new files, use ONLY fs.create with a 'content' field. Do NOT use both fs.create and fs.write for the same file path.

          Command execution:
          - exec.run: For running shell commands (tests, linters, etc.).
          - CRITICAL: exec.run steps MUST include a 'command' field with the full command string (e.g., "bundle exec rubocop", "npm test", "rspec").
          - For diagnostic/linter commands (rubocop, eslint, etc.) that return non-zero exit codes when issues are found, you MUST set 'accepted_exit_codes: [0, 1]' or 'allow_failure: true'. These commands are successful even if they find issues.
          - Example exec.run step for rubocop: {"step_id": 1, "action": "exec.run", "command": "bundle exec rubocop", "accepted_exit_codes": [0, 1], "reason": "Run rubocop to check code style", "depends_on": []}
          - IMPORTANT: When the task is to "run [command] and summarize/analyze", you should ONLY use exec.run. The command output will be automatically available - you do NOT need to read any files. Do NOT create fs.read steps for command output files.
          - NEVER use fs.read to read command output files. Command output is captured automatically when you use exec.run.

          #{empty_repo_instruction}
          Task:
          #{user_prompt}
        PROMPT
      end

      def parse_plan(response, is_empty)
        # Strip markdown code blocks if present
        cleaned = response.to_s
                          .gsub(/^```(?:json|ruby|javascript|typescript|python|java|go|rust|php|markdown|yaml|text)?\s*\n/, "")
                          .gsub(/\n```\s*$/, "")
                          .strip

        # Try to extract just the JSON object if there's extra text
        json_match = cleaned.match(/\{.*\}/m)
        json_text = json_match ? json_match[0] : cleaned

        json = JSON.parse(json_text)

        # Convert confidence from 0-1 to 0-100 if needed
        confidence = json["confidence"]
        confidence = (confidence * 100).to_i if confidence.is_a?(Float) && confidence <= 1.0

        # Extract steps - handle both array of step objects and array of strings
        steps = Array(json["steps"])
        # If steps are strings, convert to step objects
        steps = steps.map.with_index(1) do |step, idx|
          if step.is_a?(String)
            { "step_id" => idx, "action" => step, "reason" => step, "depends_on" => [] }
          else
            step
          end
        end

        # Check for BOOTSTRAP_REPO in empty repos
        if is_empty
          has_bootstrap = steps.any? do |s|
            (s.is_a?(String) && s == "BOOTSTRAP_REPO") || (s.is_a?(Hash) && (s["action"] == "BOOTSTRAP_REPO" || s["step_id"] == "BOOTSTRAP_REPO"))
          end
          unless has_bootstrap
            steps.unshift({ "step_id" => 0, "action" => "BOOTSTRAP_REPO", "reason" => "Initialize empty repository",
                            "depends_on" => [] })
          end
          # Ensure confidence >= 70 for empty repos
          confidence = [confidence, 70].max
        end

        Plan.new(
          confidence: confidence,
          steps: steps,
          blockers: Array(json["blockers"]),
          plan_id: json["plan_id"] || "plan_#{Time.now.to_i}",
          goal: json["goal"] || @user_prompt,
          assumptions: Array(json["assumptions"]),
          success_criteria: Array(json["success_criteria"]),
          rollback_strategy: json["rollback_strategy"] || "None"
        )
      rescue JSON::ParserError => e
        raise PlanningFailed, "Planner did not return valid JSON: #{e.message}"
      end
    end
  end
end
