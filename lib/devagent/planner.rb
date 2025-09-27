# frozen_string_literal: true

require "json"
require "json-schema"
require_relative "context_hints"

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
      Workflow expectations:
      - Begin by summarizing repository structure and key files.
      - Review README/CHANGELOG snippets before proposing code changes.
      - Produce multi-step plans (>=3 steps when work spans multiple edits) and mark only one step as in progress.
      - Identify implementation points using the provided survey context (instead of re-scanning) and prefer precise edits.
      - Generate or update specs when behaviour changes and schedule test runs (e.g., bundle exec rspec).
      - Call out follow-up actions such as git status or verification steps when appropriate.
      - Avoid destructive commands unless absolutely necessary; respect potential sandbox limitations.
    SYS

    DEFAULT_PLAN = Plan.new([], 0.0).freeze

    def self.plan(ctx:, task:)
      include_context = Devagent::ContextHints.context_needed?(task)
      prompt = build_prompt(ctx, task, include_context: include_context)
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

    def self.build_prompt(ctx, task, include_context: true)
      survey_section = include_context ? survey_text(ctx) : ""
      repo_context = include_context ? safe_retrieve(ctx, task) : ""

      <<~PROMPT
        #{preface_text(ctx, task)}
        #{SYSTEM}

        #{survey_block(survey_section)}
        #{context_block(repo_context, include_context)}

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

    def self.survey_block(survey_section)
      return "Repository survey skipped for conversational prompt." if survey_section.to_s.strip.empty?

      <<~SECTION
        Repository survey:
        #{survey_section}
      SECTION
    end
    private_class_method :survey_block

    def self.context_block(repo_context, include_context)
      return "Repository context skipped for conversational prompt." unless include_context

      <<~SECTION
        Repository context (truncated):
        #{repo_context}
      SECTION
    end
    private_class_method :context_block

    def self.survey_text(ctx)
      return "" unless ctx.respond_to?(:survey)

      survey = ctx.survey
      return "" unless survey

      survey.summary_text
    rescue StandardError
      ""
    end
    private_class_method :survey_text
  end
end
