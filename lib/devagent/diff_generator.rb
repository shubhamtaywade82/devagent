# frozen_string_literal: true

require_relative "prompts"

module Devagent
  # DiffGenerator asks the developer model for a minimal unified diff.
  class DiffGenerator
    def initialize(context)
      @context = context
    end

    def generate(path:, original:, goal:, reason:)
      prompt = <<~PROMPT
        #{Prompts::DIFF_SYSTEM}

        Path:
        #{path}

        Goal:
        #{goal}

        Change intent:
        #{reason}

        ORIGINAL (full file contents):
        #{original}
      PROMPT

      context.query(
        role: :developer,
        prompt: prompt,
        stream: false,
        params: { temperature: 0.0 }
      ).to_s
    end

    private

    attr_reader :context
  end
end

