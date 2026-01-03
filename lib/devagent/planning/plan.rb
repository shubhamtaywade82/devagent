# frozen_string_literal: true

module Devagent
  module Planning
    class Plan
      attr_reader :confidence, :steps, :blockers, :plan_id, :goal, :assumptions,
                  :success_criteria, :rollback_strategy, :retrieved_files

      def initialize(confidence:, steps:, blockers: [], plan_id: nil, goal: nil, assumptions: [], success_criteria: [],
                     rollback_strategy: nil, retrieved_files: [])
        @confidence = confidence.to_i
        @steps = Array(steps)
        @blockers = Array(blockers)
        @plan_id = plan_id.to_s
        @goal = goal.to_s
        @assumptions = Array(assumptions)
        @success_criteria = Array(success_criteria)
        @rollback_strategy = rollback_strategy.to_s
        @retrieved_files = Array(retrieved_files)
      end

      def valid?
        confidence.between?(0, 100) && steps.any?
      end

      # Check if a path was in the retrieved files
      def path_in_retrieved?(path)
        retrieved_files.empty? || retrieved_files.include?(path)
      end
    end
  end
end
