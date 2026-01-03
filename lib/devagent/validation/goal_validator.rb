# frozen_string_literal: true

module Devagent
  module Validation
    # GoalValidator determines if a goal has been satisfied based on
    # observable facts (repo state, test results, file changes).
    #
    # This is controller-owned verification; it must not rely on LLM judgment.
    # The validator uses deterministic checks to decide if we're done.
    #
    # @example
    #   goal = Goal.new("Add feature X")
    #   state = AgentState.initial(goal: goal.description)
    #   # ... execute plan ...
    #   GoalValidator.satisfied?(goal, state: state, repo_path: "/path/to/repo")
    #
    class GoalValidator
      # Check if the goal is satisfied based on execution state and repo state.
      #
      # @param goal [Goal] The goal to check
      # @param state [AgentState] The current agent state with observations/artifacts
      # @param repo_path [String] Path to the repository
      # @return [Hash] { satisfied: Boolean, reason: String }
      def self.satisfied?(goal, state:, repo_path:)
        new(goal, state: state, repo_path: repo_path).satisfied?
      end

      def initialize(goal, state:, repo_path:)
        @goal = goal
        @state = state
        @repo_path = repo_path
      end

      # Perform satisfaction check.
      # Returns { satisfied: true/false, reason: "..." }
      def satisfied?
        # Safety first: check for blocking conditions
        return { satisfied: false, reason: "Errors encountered" } if has_errors?
        return { satisfied: false, reason: "Clarification needed" } if needs_clarification?

        # Check success indicators in order of strength
        return { satisfied: true, reason: "Tests passed" } if tests_passed?
        return { satisfied: true, reason: "All steps completed successfully" } if all_steps_succeeded?
        return { satisfied: true, reason: "Files modified as expected" } if files_modified?

        # Fallback: Check if repo has uncommitted changes (basic progress indicator)
        return { satisfied: true, reason: "Changes made to repository" } if has_uncommitted_changes?

        { satisfied: false, reason: "No observable progress" }
      end

      private

      attr_reader :goal, :state, :repo_path

      # Check for errors that would indicate failure
      def has_errors?
        return true if state.errors.any?

        # Check for step failures in observations
        state.observations.any? do |obs|
          obs["status"] == "FAIL" && !recovery_observed_after?(obs)
        end
      end

      # Check if recovery was observed after a failure
      # (e.g., a RETRY followed by SUCCESS)
      def recovery_observed_after?(failure_obs)
        failure_index = state.observations.index(failure_obs)
        return false unless failure_index

        # Look for success after this failure
        state.observations[failure_index..].any? do |obs|
          obs["status"] == "OK" || obs["status"] == "PASS"
        end
      end

      # Check if the agent requested clarification
      def needs_clarification?
        state.clarification_asked == true
      end

      # Check if tests passed in observations
      def tests_passed?
        state.observations.any? do |obs|
          obs["type"] == "TEST_RESULT" && %w[PASS OK].include?(obs["status"])
        end
      end

      # Check if all executed steps succeeded
      def all_steps_succeeded?
        return false if state.step_results.empty?

        state.step_results.values.all? do |result|
          result.is_a?(Hash) && result["success"] == true
        end
      end

      # Check if files were modified
      def files_modified?
        return true if state.artifacts[:files_written].any?
        return true if state.artifacts[:patches_applied].to_i > 0

        false
      end

      # Check if repo has uncommitted changes (git diff not empty)
      def has_uncommitted_changes?
        return false unless repo_path && Dir.exist?(repo_path)

        # Use git diff --quiet which returns 1 if there are changes, 0 if clean
        Dir.chdir(repo_path) do
          # Check if inside git repo first
          return false unless system("git rev-parse --is-inside-work-tree > /dev/null 2>&1")

          # git diff --quiet returns exit code 1 if there are changes
          # system() returns true for exit 0, false for non-zero
          !system("git diff --quiet")
        end
      rescue StandardError
        false
      end
    end
  end
end
