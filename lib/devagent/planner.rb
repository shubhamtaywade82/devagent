# frozen_string_literal: true

require "json"

module Devagent
  Plan = Struct.new(:actions, :confidence)

  class Planner
    SYSTEM = <<~SYS
      You are a senior software engineer. Return ONLY valid JSON.

      EXAMPLE JSON:
      {
        "confidence": 0.0-1.0,
        "actions": [
          {"type": "create_file", "path": "relative/path.txt", "content": "file contents"},
          {"type": "edit_file",    "path": "relative/path.txt", "content": "full new content"},
          {"type": "run_command",  "command": "echo hello > tmp/out.txt"}
        ]
      }

      - Paths must be INSIDE the repository and relative.
      - For creating or modifying files, ALWAYS use {"type":"create_file"|"edit_file"} with full final content.
      - DO NOT use run_command to write files or use shell redirection (no '>', '>>', here-strings, tee, etc.).
      - Prefer unified diffs (apply_patch) only when explicitly requested; otherwise send full content via edit_file.
      - Keep plans minimal and safe.
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
