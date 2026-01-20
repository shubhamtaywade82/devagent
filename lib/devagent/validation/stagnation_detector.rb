# frozen_string_literal: true

require "digest"

module Devagent
  module Validation
    # StagnationDetector detects when the agent is making no progress.
    # If the same diff is observed twice in a row, we're stuck.
    #
    # This is a critical safety mechanism - without it, the agent could
    # loop forever producing the same result.
    #
    # @example
    #   detector = StagnationDetector.new
    #   detector.record_state(diff: "...", plan_fingerprint: "abc123")
    #   detector.stagnant? # => false (first observation)
    #
    #   detector.record_state(diff: "...", plan_fingerprint: "abc123")
    #   detector.stagnant? # => true (same diff repeated!)
    #
    class StagnationDetector
      MAX_HISTORY = 5

      def initialize
        @diff_history = []
        @plan_history = []
        @observations_hash_history = []
      end

      # Record the current state for stagnation detection.
      #
      # @param diff [String, nil] Current git diff
      # @param plan_fingerprint [String, nil] Fingerprint of current plan
      # @param observations [Array, nil] Current observations
      def record_state(diff: nil, plan_fingerprint: nil, observations: nil)
        # Record diff fingerprint
        diff_fp = fingerprint(diff)
        @diff_history << diff_fp
        @diff_history = @diff_history.last(MAX_HISTORY)

        # Record plan fingerprint
        if plan_fingerprint
          @plan_history << plan_fingerprint.to_s
          @plan_history = @plan_history.last(MAX_HISTORY)
        end

        # Record observations fingerprint
        return unless observations

        obs_fp = fingerprint(observations.to_s)
        @observations_hash_history << obs_fp
        @observations_hash_history = @observations_hash_history.last(MAX_HISTORY)
      end

      # Check if we're stagnant (no progress being made).
      #
      # @return [Hash] { stagnant: Boolean, reason: String }
      def stagnant?
        # Need at least 2 observations to detect stagnation
        return { stagnant: false, reason: "Insufficient history" } if @diff_history.size < 2

        # Check for repeated identical diffs
        return { stagnant: true, reason: "Same diff repeated" } if same_diff_repeated?

        # Check for repeated identical plans
        return { stagnant: true, reason: "Same plan repeated" } if same_plan_repeated?

        # Check for repeated identical observation patterns
        return { stagnant: true, reason: "Same observation pattern repeated" } if same_observations_repeated?

        { stagnant: false, reason: "Making progress" }
      end

      # Class method for simple diff comparison
      #
      # @param previous [String, nil] Previous diff
      # @param current [String, nil] Current diff
      # @return [Boolean] true if diffs are the same
      def self.same_diff?(previous, current)
        fingerprint(previous) == fingerprint(current)
      end

      # Class method to fingerprint content
      def self.fingerprint(content)
        return "empty" if content.nil? || content.to_s.strip.empty?

        Digest::SHA256.hexdigest(content.to_s.strip)
      end

      # Reset the detector (e.g., when goal changes)
      def reset!
        @diff_history.clear
        @plan_history.clear
        @observations_hash_history.clear
      end

      private

      def fingerprint(content)
        self.class.fingerprint(content)
      end

      def same_diff_repeated?
        return false if @diff_history.size < 2

        # Last two diffs are identical
        @diff_history[-1] == @diff_history[-2]
      end

      def same_plan_repeated?
        return false if @plan_history.size < 2

        # Last two plans are identical
        @plan_history[-1] == @plan_history[-2]
      end

      def same_observations_repeated?
        return false if @observations_hash_history.size < 2

        # Last two observation patterns are identical
        @observations_hash_history[-1] == @observations_hash_history[-2]
      end
    end
  end
end
