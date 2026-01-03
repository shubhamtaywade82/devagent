# frozen_string_literal: true

require "json"
require_relative "../planning_failed"
require_relative "../context"
require_relative "plan"

module Devagent
  module Planning
    class Planner
      MIN_CONFIDENCE = 50

      # Intents that require mandatory retrieval before planning
      RETRIEVAL_REQUIRED_INTENTS = %w[CODE_EDIT DEBUG CODE_REVIEW].freeze

      def initialize(repo_path:, context:, retrieval_controller: nil)
        @repo_path = repo_path
        @context = context
        @retrieval_controller = retrieval_controller
        # Try to use llama3.1:8b, but fall back to configured planner_model if not available
        @preferred_model = "llama3.1:8b"
        @planner_model = context.config["planner_model"] || "llama3.1:8b"
      end

      # Plan with retrieval enforcement
      #
      # @param user_prompt [String] The user's task
      # @param intent [String] The classified intent (optional)
      # @return [Plan] The generated plan
      def call(user_prompt, intent: nil)
        @user_prompt = user_prompt
        @intent = intent

        # Check if repo is empty
        is_empty = repo_empty?

        # Get retrieved files (enforced for certain intents)
        retrieved = retrieve_context(user_prompt, is_empty: is_empty, intent: intent)

        response = query_planner(user_prompt, is_empty, retrieved_files: retrieved)

        plan = parse_plan(response, is_empty, retrieved_files: retrieved)

        unless plan.valid? && plan.confidence >= MIN_CONFIDENCE
          raise PlanningFailed, "Planning confidence too low: #{plan.confidence}% (minimum: #{MIN_CONFIDENCE}%)"
        end

        plan
      end

      private

      attr_reader :retrieval_controller, :repo_path, :context, :planner_model, :preferred_model, :user_prompt, :intent

      # Check if we're running inside the devagent gem itself
      def devagent_gem?
        gem_path = File.expand_path(repo_path)
        # Check for devagent-specific files/directories
        File.exist?(File.join(gem_path, "lib/devagent")) &&
          File.exist?(File.join(gem_path, ".devagent.yml")) &&
          File.exist?(File.join(gem_path, "exe/devagent"))
      end

      # Retrieve context files based on intent and repo state
      def retrieve_context(user_prompt, is_empty:, intent:)
        return [] if is_empty

        # First, try to find files by exact name match in common locations
        # This helps when user mentions a filename like "hello_world.rb"
        # by searching in playground/, lib/, src/, etc.
        exact_matches = find_files_by_name(user_prompt)

        # If no retrieval controller, fall back to index directly
        if retrieval_controller.nil?
          semantic_results = safe_retrieve_from_index(user_prompt)
          # Combine exact matches with semantic results, prioritizing exact matches
          return (exact_matches + semantic_results).uniq
        end

        # Check if retrieval is mandatory for this intent
        mandatory = RETRIEVAL_REQUIRED_INTENTS.include?(intent.to_s.upcase)

        result = retrieval_controller.retrieve_for_goal(
          user_prompt,
          intent: intent || "GENERAL",
          limit: 6
        )

        if result[:skip_reason] == :repo_empty
          context.tracer&.event("retrieval_skipped", reason: "repo_empty")
          return exact_matches
        end

        if result[:skip_reason] && mandatory
          context.tracer&.event("retrieval_required_but_skipped",
                                reason: result[:skip_reason],
                                intent: intent)
        end

        semantic_files = result[:files] || []
        # Combine exact matches with semantic results, prioritizing exact matches
        (exact_matches + semantic_files).uniq
      end

      def safe_retrieve_from_index(user_prompt)
        return [] unless context.respond_to?(:index)

        snippets = context.index.retrieve(user_prompt, limit: 6)
        snippets.map { |s| s["path"] }.uniq
      rescue StandardError
        []
      end

      # Find files by exact name match in common locations
      # This helps when user mentions a filename like "hello_world.rb"
      # by searching in playground/, lib/, src/, etc. (in priority order)
      def find_files_by_name(user_prompt)
        # Extract potential filenames from the prompt
        # Look for patterns like "hello_world.rb", "update hello_world.rb", etc.
        filename_patterns = [
          /\b([a-zA-Z0-9_\-.]+\.[a-zA-Z0-9]+)\b/, # filename.ext
          /\b(?:update|edit|modify|change|read|open|create|add|refactor|improve)\s+([a-zA-Z0-9_\-.]+\.[a-zA-Z0-9]+)\b/i, # action filename.ext
          /\b([a-zA-Z0-9_\-.]+\.[a-zA-Z0-9]+)\s+(?:to|in|at|from|with|follow|using)\b/i # filename.ext preposition
        ]

        filenames = []
        filename_patterns.each do |pattern|
          matches = user_prompt.scan(pattern)
          matches.each { |match| filenames << match[0] if match[0] }
        end

        return [] if filenames.empty?

        # Determine workspace based on context
        # If we're in the devagent gem itself, prioritize playground/
        # Otherwise, use standard locations
        is_devagent_gem = devagent_gem?
        common_locations = if is_devagent_gem
                             # In devagent gem: playground/ is the workspace
                             %w[playground lib src app spec test tests]
                           else
                             # In external project: standard locations
                             %w[lib src app spec test tests playground]
                           end

        found_files = []
        filenames.each do |filename|
          # First check if it's already a full path
          if filename.include?("/")
            full_path = File.join(repo_path, filename)
            if File.exist?(full_path) && context.tool_bus.safety.allowed?(filename)
              found_files << filename
              next
            end
          end

          # Search in common locations (priority order)
          common_locations.each do |location|
            test_path = "#{location}/#{filename}"
            full_path = File.join(repo_path, test_path)
            if File.exist?(full_path) && context.tool_bus.safety.allowed?(test_path)
              found_files << test_path
              break # Found in this location, no need to check others
            end
          end

          # Also check root directory
          root_path = filename
          full_path = File.join(repo_path, root_path)
          if File.exist?(full_path) && context.tool_bus.safety.allowed?(root_path) && !found_files.include?(root_path)
            found_files << root_path
          end
        end

        found_files.uniq
      end

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

      def query_planner(user_prompt, is_empty, retrieved_files: [])
        prompt = build_prompt(user_prompt, is_empty, retrieved_files: retrieved_files)

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

      def build_prompt(user_prompt, is_empty, retrieved_files: [])
        is_devagent_gem = devagent_gem?
        workspace_dir = is_devagent_gem ? "playground" : "lib"

        parts = []
        parts << "PLANNING ENGINE - Return JSON only, no markdown."
        parts << ""

        # Workspace context
        if is_devagent_gem
          parts << "WORKSPACE: playground/ (devagent gem). New files MUST use playground/, NOT lib/."
        else
          parts << "WORKSPACE: Standard project (lib/, src/, app/, etc.)"
        end
        parts << ""

        # JSON structure
        parts << "JSON: {confidence: 0-100, steps: [{step_id, action, path/command/content, reason, depends_on}], blockers: []}"
        parts << ""

        # Actions reference
        parts << "Actions:"
        parts << "- fs.read: existing files only"
        parts << "- fs.create: new files with complete 'content' field"
        parts << "- fs.write: edit existing (MUST depends_on fs.read of same path)"
        parts << "- exec.run: shell commands (requires 'command' field)"
        parts << ""

        # Key rules - CRITICAL section for rules that cause plan rejection
        parts << "CRITICAL RULES (violations = plan rejection):"
        parts << "1. fs.write MUST depends_on the step_id of fs.read for SAME path"
        parts << "   Example: step 1 fs.read 'foo.rb' → step 2 fs.write 'foo.rb' depends_on: [1]"
        parts << "2. fs.create for new files only (include complete 'content' field)"
        parts << "3. Never fs.write after fs.create for same file"
        parts << ""
        parts << "Linter tips: accepted_exit_codes: [0, 1], then 'rubocop -a' to auto-fix"
        parts << ""

        # Retrieved files
        if retrieved_files.any?
          parts << "RETRIEVED FILES: #{retrieved_files.join(", ")}"
          parts << "Use these paths for fs.read when they match the task."
          parts << ""
        end

        # Empty repo
        if is_empty
          parts << "EMPTY REPO: Set confidence >= 70, first step = BOOTSTRAP_REPO"
          parts << ""
        end

        parts << "Task: #{user_prompt}"

        parts.join("\n")
      end

      def parse_plan(response, is_empty, retrieved_files: [])
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
          rollback_strategy: json["rollback_strategy"] || "None",
          retrieved_files: retrieved_files
        )
      rescue JSON::ParserError => e
        raise PlanningFailed, "Planner did not return valid JSON: #{e.message}"
      end
    end
  end
end
