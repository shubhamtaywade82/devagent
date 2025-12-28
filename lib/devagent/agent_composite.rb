# frozen_string_literal: true

module Devagent
  # Composite pattern for multi-agent orchestration.
  #
  # Allows treating individual agents (Planner, Developer, Tester, Reviewer) as a single
  # composite agent that can be orchestrated together.
  #
  # Usage:
  #   planner = PlannerAgent.new(context)
  #   developer = DeveloperAgent.new(context)
  #   tester = TesterAgent.new(context)
  #
  #   composite = AgentComposite.new([planner, developer, tester])
  #   result = composite.run(task)
  #
  # Benefits:
  #   - Treat multiple agents as one unit
  #   - Easy to add/remove agents
  #   - Consistent interface across agent types
  #   - Enables agent chain-of-thought workflows
  #
  # Example:
  #   # Simple sequential execution
  #   composite.run(task)  # planner → developer → tester
  #
  #   # Parallel execution (future)
  #   composite.run_parallel(task)  # planner, developer, tester all at once
  #
  #   # Conditional execution
  #   composite.run_conditional(task) do |result|
  #     if result[:tests_passed]
  #       # continue
  #     else
  #       # replan
  #     end
  #   end
  class AgentComposite
    attr_reader :agents

    def initialize(agents)
      @agents = Array(agents)
      validate_agents!
    end

    # Run all agents sequentially
    #
    # @param task [String] The task to execute
    # @return [Hash] Results from all agents
    def run(task)
      results = {}

      @agents.each do |agent|
        agent_name = agent_name_for(agent)
        results[agent_name] = agent.process(task, results)
      end

      results
    end

    # Run agents with conditional logic
    #
    # @param task [String] The task to execute
    # @yield [Hash] The results from each agent
    # @yieldparam results [Hash] Cumulative results
    # @yieldreturn [Symbol] What to do next (:continue, :replan, :stop)
    def run_conditional(task)
      results = {}

      @agents.each do |agent|
        agent_name = agent_name_for(agent)
        agent_result = agent.process(task, results)
        results[agent_name] = agent_result

        decision = yield(results)
        break if decision == :stop

        if decision == :replan
          results.clear
          return run_conditional(task, &block)
        end
      end

      results
    end

    # Add an agent to the composite
    #
    # @param agent [Object] Agent object that responds to #process
    def add(agent)
      validate_agent!(agent)
      @agents << agent
    end

    # Remove an agent from the composite
    #
    # @param agent [Object] Agent to remove
    def remove(agent)
      @agents.delete(agent)
    end

    # Get agent by name
    #
    # @param name [Symbol] Agent name (:planner, :developer, :tester, etc.)
    # @return [Object] Agent object or nil
    def get(name)
      @agents.find { |agent| agent_name_for(agent) == name }
    end

    # Check if composite contains an agent
    #
    # @param name [Symbol] Agent name
    # @return [Boolean]
    def contains?(name)
      !get(name).nil?
    end

    private

    def validate_agents!
      @agents.each { |agent| validate_agent!(agent) }
    end

    def validate_agent!(agent)
      return if agent.respond_to?(:process)

      raise Error, "Agent must respond to #process, got: #{agent.class}"
    end

    def agent_name_for(agent)
      agent.class.name.split("::").last.underscore.to_sym
    rescue StandardError
      :unknown
    end
  end

  # Base class for agents that work in the composite
  #
  # All agents must implement:
  # - #process(task, previous_results) -> result hash
  #
  # Example:
  #   class PlannerAgent < AgentBase
  #     def process(task, previous_results = {})
  #       plan = planner.plan(task)
  #       { summary: plan.summary, actions: plan.actions, confidence: plan.confidence }
  #     end
  #   end
  class AgentBase
    attr_reader :context

    def initialize(context)
      @context = context
    end

    # Process a task and return results
    #
    # Must be implemented by subclasses.
    #
    # @param task [String] The task to process
    # @param previous_results [Hash] Results from previous agents
    # @return [Hash] Processing results
    def process(task, previous_results = {})
      raise NotImplementedError, "Subclass must implement #process"
    end
  end

  # Concrete implementation of PlannerAgent for use in composite
  class PlannerAgent < AgentBase
    def process(task, _previous_results = {})
      planner = Planner.new(context)
      plan = planner.plan(task)

      {
        summary: plan.summary,
        actions: plan.actions,
        confidence: plan.confidence,
        agent: :planner
      }
    end
  end

  # Concrete implementation of DeveloperAgent for use in composite
  class DeveloperAgent < AgentBase
    def process(_task, previous_results = {})
      return {} if previous_results[:planner]&.dig(:actions).nil?

      actions = previous_results[:planner][:actions]
      executed = []

      context.tool_bus.reset!
      actions.each do |action|
        context.tracer.event("execute_action", action: action)
        context.tool_bus.invoke(action)
        executed << action
      rescue StandardError => e
        context.tracer.event("action_failed", action: action, error: e.message)
        return { error: e.message, agent: :developer }
      end

      {
        executed: executed,
        changes_made: context.tool_bus.changes_made?,
        agent: :developer
      }
    end
  end

  # Concrete implementation of TesterAgent for use in composite
  class TesterAgent < AgentBase
    def process(_task, previous_results = {})
      return { skipped: true, agent: :tester } unless previous_results[:developer]&.dig(:changes_made)

      command = context.config.dig("auto", "test_command") || "bundle exec rspec"
      result = context.tool_bus.run_tests("command" => command)

      {
        result: result,
        passed: result == :ok,
        agent: :tester
      }
    rescue StandardError => e
      { result: :failed, error: e.message, agent: :tester }
    end
  end
end

# Add String#underscore for agent_name_for
unless String.instance_methods.include?(:underscore)
  class String
    def underscore
      gsub(/([A-Z])/, '_\1').downcase.gsub(/^_/, "")
    end
  end
end
