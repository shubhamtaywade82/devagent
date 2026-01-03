# frozen_string_literal: true

module Devagent
  # Goal represents the user's intent that the agent is trying to satisfy.
  # This is the primary object that drives the agent's retry loop.
  # The agent doesn't "finish steps" - it tries to reach this GOAL
  # by iterating until success or a hard stop.
  #
  # @example
  #   goal = Goal.new("Add a hello world function to lib/greet.rb")
  #   goal.description # => "Add a hello world function to lib/greet.rb"
  #
  class Goal
    attr_reader :description, :created_at

    # @param description [String] The user's intent/task description
    def initialize(description)
      raise ArgumentError, "Goal description cannot be empty" if description.to_s.strip.empty?

      @description = description.to_s.strip
      @created_at = Time.now
    end

    # Returns a string representation for logging/debugging
    def to_s
      description
    end

    # Equality check based on description
    def ==(other)
      return false unless other.is_a?(Goal)

      description == other.description
    end

    alias eql? ==

    def hash
      description.hash
    end
  end
end
