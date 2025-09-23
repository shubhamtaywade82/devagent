# frozen_string_literal: true

require "json"

module Devagent
  Plan = Struct.new(:actions, :confidence)

  class Planner
    SYSTEM = <<~SYS
      You are a senior software engineer. Return ONLY valid JSON.

      JSON:
      {
        "confidence": 0.0-1.0,
        "actions": [
          {"type": "create_file", "path": "relative/path.txt", "content": "file contents"},
          {"type": "edit_file",    "path": "relative/path.txt", "content": "full new content"},
          {"type": "run_command",  "command": "echo hello > tmp/out.txt"}
        ]
      }

      Constraints:
      - All paths MUST be relative and inside the repository.
      - Prefer small, minimal sets of actions.
      - For edits, provide the entire final file content (no partial patches).
      - If no actions are appropriate, return {"confidence": 0.0, "actions": []}.
    SYS

    def self.plan(ctx:, task:)
      prompt = <<~P
        #{SYSTEM}

        Task from user:
        #{task}

        Return JSON only.
      P

      raw = invoke_llm(ctx, prompt)
      json = parse_json(raw)
      Plan.new(
        Array(json["actions"] || []),
        (json["confidence"] || 0.0).to_f
      )
    end

    def self.invoke_llm(ctx, prompt)
      ctx.llm.call(prompt).to_s
    rescue StandardError
      ""
    end
    private_class_method :invoke_llm

    def self.parse_json(raw)
      return {"actions" => [], "confidence" => 0.0} if raw.to_s.strip.empty?
      JSON.parse(raw)
    rescue JSON::ParserError
      {"actions" => [], "confidence" => 0.0}
    end
    private_class_method :parse_json
  end
end
