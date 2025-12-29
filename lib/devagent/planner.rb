# frozen_string_literal: true

require "json"
require "json-schema"
require_relative "prompts"

module Devagent
  Plan = Struct.new(
    :plan_id,
    :goal,
    :assumptions,
    :steps,
    :success_criteria,
    :rollback_strategy,
    :confidence,
    :actions,
    :summary,
    keyword_init: true
  )

  # Planner coordinates with the planning and review models to produce
  # validated actions.
  class Planner
    PLAN_SCHEMA_V2 = {
      "type" => "object",
      # NOTE: keep schema permissive for local models; controller performs strict validation later.
      "required" => %w[plan_id assumptions steps success_criteria rollback_strategy confidence],
      "properties" => {
        "plan_id" => { "type" => "string" },
        "goal" => { "type" => %w[string null] },
        "summary" => { "type" => %w[string null] },
        "assumptions" => { "type" => "array", "items" => { "type" => "string" } },
        "steps" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            # path/command/content are tool-specific; do not require them at schema-level.
            "required" => %w[step_id action reason depends_on],
            "properties" => {
              "step_id" => { "type" => "integer", "minimum" => 1 },
              "action" => { "type" => "string" },
              "path" => { "type" => %w[string null] },
              "command" => { "type" => %w[string null] },
              "content" => { "type" => %w[string null] },
              "accepted_exit_codes" => { "type" => %w[array null], "items" => { "type" => "integer" } },
              "allow_failure" => { "type" => %w[boolean null] },
              "reason" => { "type" => "string" },
              "depends_on" => { "type" => "array", "items" => { "type" => "integer", "minimum" => 0 } }
            }
          }
        },
        "success_criteria" => { "type" => "array", "items" => { "type" => "string" } },
        "rollback_strategy" => { "type" => "string" },
        "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
      }
    }.freeze

    PLAN_SCHEMA_V1 = {
      "type" => "object",
      "required" => %w[confidence actions],
      "properties" => {
        "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 },
        "summary" => { "type" => "string" },
        "actions" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => ["type"],
            "properties" => {
              "type" => { "type" => "string" },
              "args" => { "type" => %w[object null] }
            }
          }
        }
      }
    }.freeze

    PLAN_SCHEMA = {
      "anyOf" => [PLAN_SCHEMA_V2, PLAN_SCHEMA_V1]
    }.freeze

    REVIEW_SCHEMA = {
      "type" => "object",
      "required" => %w[approved issues],
      "properties" => {
        "approved" => { "type" => "boolean" },
        "issues" => { "type" => "array", "items" => { "type" => "string" } }
      }
    }.freeze
    def initialize(context, streamer: nil)
      @context = context
      @streamer = streamer
    end

    def plan(task, controller_feedback: nil, visible_tools: nil)
      attempts = 0
      feedback = nil
      raw_plan = nil

      loop do
        raw_plan = generate_plan(task, feedback, controller_feedback: controller_feedback, visible_tools: visible_tools)
        payload = parse_plan(raw_plan)
        review = review_plan(task, raw_plan)
        if review["approved"] || attempts >= 1
          steps = Array(payload["steps"]).map do |step|
            {
              "step_id" => step["step_id"],
              "action" => step["action"],
              "path" => step["path"],
              "command" => step["command"],
              "content" => step["content"],
              "accepted_exit_codes" => step["accepted_exit_codes"],
              "allow_failure" => step["allow_failure"],
              "reason" => step["reason"],
              "depends_on" => Array(step["depends_on"])
            }
          end

          # Back-compat: allow legacy "actions" plans by wrapping into step form.
          if steps.empty? && payload["actions"]
            steps = Array(payload["actions"]).each_with_index.map do |action, idx|
              {
                "step_id" => idx + 1,
                "action" => action["type"],
                "path" => action.dig("args", "path"),
                "command" => action.dig("args", "command"),
                "reason" => "legacy action",
                "depends_on" => []
              }
            end
          end

          break Plan.new(
            plan_id: payload["plan_id"],
            goal: payload["goal"] || payload["summary"],
            assumptions: Array(payload["assumptions"]),
            steps: steps,
            success_criteria: Array(payload["success_criteria"]),
            rollback_strategy: payload["rollback_strategy"].to_s,
            confidence: payload["confidence"].to_f,
            summary: (payload["goal"] || payload["summary"]).to_s,
            actions: [] # no longer used for execution
          )
        end

        attempts += 1
        feedback = Array(review["issues"]).reject(&:empty?)
        context.tracer.event("plan_review_rejected", issues: feedback)
      end
    rescue StandardError => e
      context.tracer.event("planner_error", message: e.message)
      Plan.new(summary: "planning failed", actions: [], confidence: 0.0)
    end

    private

    attr_reader :context, :streamer

    def generate_plan(task, feedback, controller_feedback:, visible_tools:)
      prompt = build_prompt(task, feedback, controller_feedback: controller_feedback, visible_tools: visible_tools)
      response_format = json_schema_format(PLAN_SCHEMA) if context.provider_for(:planner) == "openai"
      return stream_plan(prompt, response_format) if streamer

      context.query(
        role: :planner,
        prompt: prompt,
        stream: false,
        response_format: response_format,
        params: { temperature: 0.1 }
      )
    end

    def review_plan(task, raw_plan)
      prompt = build_review_prompt(task, raw_plan)
      response_format = json_schema_format(REVIEW_SCHEMA) if context.provider_for(:reviewer) == "openai"
      review_raw = context.query(
        role: :reviewer,
        prompt: prompt,
        stream: false,
        response_format: response_format,
        params: { temperature: 0.1 }
      )
      parse_review(review_raw)
    rescue StandardError => e
      context.tracer.event("plan_review_error", message: e.message)
      { "approved" => true, "issues" => [] }
    end

    def parse_plan(raw)
      # Strip markdown code blocks if present
      cleaned = raw.to_s
                   .gsub(/^```(?:json|ruby|javascript|typescript|python|java|go|rust|php|markdown|yaml|text)?\s*\n/, "")
                   .gsub(/\n```\s*$/, "")
                   .strip

      json = JSON.parse(cleaned)
      JSON::Validator.validate!(PLAN_SCHEMA, json)
      json
    rescue JSON::ParserError, JSON::Schema::ValidationError => e
      context.tracer.event("plan_invalid_json", message: e.message, raw: raw)
      {
        "confidence" => 0.0,
        "plan_id" => "",
        "goal" => "",
        "assumptions" => ["invalid plan JSON/schema"],
        "steps" => [],
        "success_criteria" => [],
        "rollback_strategy" => ""
      }
    end

    def parse_review(raw)
      # Strip markdown code blocks if present, and extract JSON if there's extra text
      cleaned = raw.to_s
                   .gsub(/^```(?:json|ruby|javascript|typescript|python|java|go|rust|php|markdown|yaml|text)?\s*\n/, "")
                   .gsub(/\n```\s*$/, "")
                   .strip

      # Try to extract just the JSON object if there's extra text after it
      json_match = cleaned.match(/\{.*\}/m)
      json_text = json_match ? json_match[0] : cleaned

      json = JSON.parse(json_text)
      JSON::Validator.validate!(REVIEW_SCHEMA, json)
      json
    rescue JSON::ParserError, JSON::Schema::ValidationError => e
      context.tracer.event("plan_review_invalid", message: e.message, raw: raw)
      { "approved" => true, "issues" => [] }
    end

    def build_prompt(task, feedback, controller_feedback:, visible_tools:)
      # Context assembly discipline: after we have controller feedback (i.e., post-iteration),
      # do not keep expanding context with long history or broad retrieval. Feed only reduced observations.
      retrieved = ""
      history = ""
      if controller_feedback.to_s.strip.empty?
        # Reduce context size to avoid prompt truncation (Ollama limit ~4096 tokens)
        retrieved = context.index.retrieve(task, limit: 4).map do |snippet|
          # Truncate long snippets to ~500 chars each
          text = snippet["text"].to_s
          text = "#{text[0..500]}... (truncated)" if text.length > 500
          "#{snippet["path"]}:\n#{text}\n---"
        end.join("\n")

        # Reduce history to 3 turns to save tokens
        history = context.session_memory.last_turns(3).map do |turn|
          content = turn["content"].to_s
          # Truncate long history entries
          content = "#{content[0..200]}... (truncated)" if content.length > 200
          "#{turn["role"]}: #{content}"
        end.join("\n")
      end

      plugin_guidance = context.plugins.filter_map do |plugin|
        plugin.on_prompt(context, task) if plugin.respond_to?(:on_prompt)
      end.join("\n")

      tool_values = if visible_tools
                      Array(visible_tools)
                    elsif context.tool_registry.respond_to?(:tools_for_phase)
                      context.tool_registry.tools_for_phase(:planning).values
                    else
                      context.tool_registry.tools.values
                    end

      # Use compact contracts to reduce prompt size
      tool_contracts = tool_values.map do |tool|
        if tool.respond_to?(:to_compact_contract_hash)
          tool.to_compact_contract_hash
        elsif tool.respond_to?(:to_contract_hash)
          # Fallback: create compact version manually
          contract = tool.to_contract_hash
          {
            "name" => contract["name"],
            "category" => contract["category"],
            "description" => contract["description"],
            "inputs" => contract["inputs"],
            "outputs" => contract["outputs"],
            "dependencies" => contract["dependencies"] || {}
          }
        else
          { "name" => tool.name, "description" => tool.description }
        end
      end
      # Use compact JSON (no pretty printing) to save tokens
      tools_json = JSON.generate(tool_contracts)

      feedback_section = if feedback && !Array(feedback).empty?
                           "Known issues from reviewer:\n#{Array(feedback).join("\n")}"
                         else
                           ""
                         end

      controller_section = if controller_feedback && !controller_feedback.to_s.strip.empty?
                             "Controller observations (normalized):\n#{controller_feedback}"
                           else
                             ""
                           end

      <<~PROMPT
        #{Prompts::PLANNER_SYSTEM}

        #{plugin_guidance}

        You have access to the following tools. Each tool MUST be used strictly according to its contract.
        Never invent tools. Never skip dependencies. Never assume side effects.

        Tools (JSON):
        #{tools_json}

        Recent conversation:
        #{history}

        Repository context:
        #{retrieved}

        #{feedback_section}
        #{controller_section}

        Task:
        #{task}
      PROMPT
    end

    def build_review_prompt(task, raw_plan)
      <<~PROMPT
        #{Prompts::PLANNER_REVIEW_SYSTEM}

        Task:
        #{task}

        Proposed plan JSON:
        #{raw_plan}
      PROMPT
    end

    def stream_plan(prompt, response_format)
      streamer.with_stream(:planner, markdown: false, silent: true) do |push|
        raw = context.query(
          role: :planner,
          prompt: prompt,
          stream: false,
          response_format: response_format,
          params: { temperature: 0.1 }
        )

        raw.each_char { |char| push.call(char) } if push

        raw
      end
    end

    def json_schema_format(schema)
      {
        type: "json_schema",
        json_schema: {
          name: "devagent_schema",
          schema: schema
        }
      }
    end
  end
end
