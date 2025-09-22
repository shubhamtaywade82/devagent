# frozen_string_literal: true

require "json"
require "json-schema"

module Devagent
  Plan = Struct.new(:actions, :confidence)

  # Planner asks the LLM for an actionable plan and validates the response.
  class Planner
    ACTION_SCHEMA = {
      "type" => {
        "type" => "string",
        "enum" => %w[edit_file create_file apply_patch run_command generate_tests migrate]
      },
      "path" => { "type" => %w[string null] },
      "whole_file" => { "type" => %w[boolean null] },
      "content" => { "type" => %w[string null] },
      "patch" => { "type" => %w[string null] },
      "command" => { "type" => %w[string null] },
      "notes" => { "type" => %w[string null] }
    }.freeze

    PLAN_SCHEMA = {
      "type" => "object",
      "required" => %w[actions confidence],
      "properties" => {
        "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 },
        "actions" => { "type" => "array", "items" => { "type" => "object", "properties" => ACTION_SCHEMA } }
      }
    }.freeze

    SYSTEM = <<~SYS
      You are a senior software engineer. Return ONLY valid JSON.
      JSON:
      {
        "confidence": 0.0-1.0,
        "actions": [
          {"type": "create_file", "path": "relative/path.rb", "content": "..."},
          {"type": "edit_file", "path": "app/models/user.rb", "whole_file": true, "content": "..."},
          {"type": "apply_patch", "path": "app/models/user.rb", "patch": "UNIFIED DIFF"},
          {"type": "generate_tests", "path": "app/models/user.rb"},
          {"type": "run_command", "command": "bundle exec rspec"},
          {"type": "migrate"}
        ]
      }
      Constraints:
      - Paths must be INSIDE the repository and relative.
      - Prefer unified diffs for small changes; use whole_file for large rewrites.
      - For Rails, ensure migrations are reversible; add RSpec when needed.
      - Keep plans minimal and safe.
    SYS

    DEFAULT_PLAN = Plan.new([], 0.0).freeze

    def self.plan(ctx:, task:)
      prompt = build_prompt(ctx, task)
      json = parse_plan(invoke_llm(ctx, prompt))
      actions = json.fetch("actions", [])
      confidence = json.fetch("confidence", 0.0).to_f
      Plan.new(actions, confidence)
    end

    def self.safe_retrieve(ctx, task)
      return "" unless ctx.respond_to?(:index) && ctx.index.respond_to?(:retrieve)

      Array(ctx.index.retrieve(task, limit: 12)).join("\n\n")
    rescue StandardError
      ""
    end
    private_class_method :safe_retrieve

    def self.invoke_llm(ctx, prompt)
      llm = ctx.llm
      return "" unless llm.respond_to?(:call)

      llm.call(prompt).to_s
    rescue StandardError
      ""
    end
    private_class_method :invoke_llm

    def self.parse_plan(raw)
      return { "actions" => [], "confidence" => 0.0 } if raw.to_s.strip.empty?

      json = JSON.parse(raw)
      JSON::Validator.validate!(PLAN_SCHEMA, json)
      json
    rescue JSON::ParserError, JSON::Schema::SchemaError, JSON::Schema::ValidationError
      { "actions" => [], "confidence" => 0.0 }
    end
    private_class_method :parse_plan

    def self.build_prompt(ctx, task)
      <<~PROMPT
        #{preface_text(ctx, task)}
        #{SYSTEM}

        Repository context (truncated):
        #{safe_retrieve(ctx, task)}

        Task from user:
        #{task}

        Return JSON only.
      PROMPT
    end
    private_class_method :build_prompt

    def self.preface_text(ctx, task)
      Array(ctx.plugins).filter_map do |plugin|
        next unless plugin.respond_to?(:on_prompt)

        plugin.on_prompt(ctx, task)
      end.join("\n")
    end
    private_class_method :preface_text
  end
end
