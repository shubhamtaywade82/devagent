# frozen_string_literal: true

require "json"

module Devagent
  # Builder pattern for constructing complex prompts in a composable, readable way.
  #
  # Usage:
  #   PromptBuilder.new
  #     .with_system_prompt(:planner)
  #     .with_memory(context.session_memory)
  #     .with_context(retrieved_code)
  #     .with_user_input(task)
  #     .with_feedback(feedback)
  #     .with_tools(context.tool_registry)
  #     .build
  #
  # Benefits:
  #   - Composability: add/remove sections easily
  #   - Clarity: self-documenting prompt structure
  #   - Testability: can verify each section independently
  #   - Extensibility: new sections don't break existing code
  class PromptBuilder
    attr_reader :sections

    def initialize
      @sections = {}
    end

    # Add a system prompt template (e.g., :planner, :developer, :reviewer)
    def with_system_prompt(role)
      @sections[:system] = system_prompt_for(role)
      self
    end

    # Add conversation memory/history
    def with_memory(session_memory, limit: 8)
      turns = session_memory.last_turns(limit)
      @sections[:memory] = format_turns(turns)
      self
    end

    # Add retrieved code context from index
    def with_context(retrieved_code)
      formatted = retrieved_code.map do |snippet|
        "#{snippet["path"]}:\n#{snippet["text"]}\n---"
      end.join("\n")
      @sections[:context] = formatted unless formatted.empty?
      self
    end

    # Add plugin-specific guidance
    def with_plugin_guidance(context, task)
      guidance = context.plugins.filter_map do |plugin|
        plugin.on_prompt(context, task) if plugin.respond_to?(:on_prompt)
      end.join("\n")
      @sections[:plugin_guidance] = guidance unless guidance.empty?
      self
    end

    # Add available tools
    def with_tools(tool_registry, phase: :planning)
      tool_values = if tool_registry.respond_to?(:visible_tools_for_phase)
                      tool_registry.visible_tools_for_phase(phase)
                    else
                      tool_registry.tools.values
                    end

      tool_contracts = tool_values.map do |tool|
        if tool.respond_to?(:to_contract_hash)
          tool.to_contract_hash
        else
          { "name" => tool.name,
            "description" => tool.description }
        end
      end

      @sections[:tools] = JSON.pretty_generate(tool_contracts)
      self
    end

    # Add user's task/prompt
    def with_user_input(input)
      @sections[:task] = input
      self
    end

    # Add reviewer feedback
    def with_feedback(feedback)
      issues = Array(feedback).reject(&:empty?)
      return self if issues.empty?

      @sections[:feedback] = "Known issues from reviewer:\n#{issues.join("\n")}"
      self
    end

    # Add custom section
    def with_section(name, content)
      @sections[name] = content unless content.to_s.empty?
      self
    end

    # Build the final prompt string
    def build
      parts = []

      parts << @sections[:system] if @sections[:system]
      parts << "" # blank line

      parts << @sections[:plugin_guidance] if @sections[:plugin_guidance]
      parts << "" if @sections[:plugin_guidance]

      parts << "Available tools:" if @sections[:tools]
      parts << @sections[:tools] if @sections[:tools]
      parts << "" if @sections[:tools]

      parts << "Recent conversation:" if @sections[:memory]
      parts << @sections[:memory] if @sections[:memory]
      parts << "" if @sections[:memory]

      parts << "Repository context:" if @sections[:context]
      parts << @sections[:context] if @sections[:context]
      parts << "" if @sections[:context]

      parts << @sections[:feedback] if @sections[:feedback]
      parts << "" if @sections[:feedback]

      parts << "Task:" if @sections[:task]
      parts << @sections[:task] if @sections[:task]

      parts.reject(&:empty?).join("\n")
    end

    private

    def system_prompt_for(role)
      case role
      when :planner
        Prompts::PLANNER_SYSTEM
      when :developer
        Prompts::DEVELOPER_SYSTEM
      when :reviewer
        Prompts::PLANNER_REVIEW_SYSTEM
      else
        ""
      end
    end

    def format_turns(turns)
      turns.map { |turn| "#{turn["role"]}: #{turn["content"]}" }.join("\n")
    end
  end
end
