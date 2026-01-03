# frozen_string_literal: true

module Devagent
  module Planning
    class Plan
      attr_reader :confidence, :steps, :blockers, :plan_id, :goal, :assumptions, :success_criteria, :rollback_strategy

      def initialize(confidence:, steps:, blockers: [], plan_id: nil, goal: nil, assumptions: [], success_criteria: [],
                     rollback_strategy: nil)
        @confidence = confidence.to_i
        @steps = Array(steps)
        @blockers = Array(blockers)
        @plan_id = plan_id.to_s
        @goal = goal.to_s
        @assumptions = Array(assumptions)
        @success_criteria = Array(success_criteria)
        @rollback_strategy = rollback_strategy.to_s
      end

      def valid?
        confidence.between?(0, 100) && steps.any?
      end
    end
  end
end
