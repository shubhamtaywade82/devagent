# frozen_string_literal: true

require "json"
require "json-schema"
require_relative "prompts"

module Devagent
  Plan = Struct.new(:summary, :actions, :confidence, keyword_init: true)

  # Planner coordinates with the planning and review models to produce
  # validated actions.
  class Planner
    PLAN_SCHEMA = {
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
              "args" => { "type" => ["object", "null"] }
            }
          }
        }
      }
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

    def plan(task)
      attempts = 0
      feedback = nil
      raw_plan = nil

      loop do
        raw_plan = generate_plan(task, feedback)
        payload = parse_plan(raw_plan)
        review = review_plan(task, raw_plan)
        break Plan.new(summary: payload["summary"], actions: payload["actions"] || [], confidence: payload["confidence"].to_f) if review["approved"] || attempts >= 1

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

    def generate_plan(task, feedback)
      prompt = build_prompt(task, feedback)
      response_format = json_schema_format(PLAN_SCHEMA) if context.provider_for(:planner) == "openai"
      if streamer
        streamer.with_stream(:planner) do |on_token|
          context.query(
            role: :planner,
            prompt: prompt,
            stream: true,
            response_format: response_format,
            params: { temperature: 0.1 }
          ) do |token|
            on_token.call(token)
          end
        end
      else
        context.query(
          role: :planner,
          prompt: prompt,
          stream: false,
          response_format: response_format,
          params: { temperature: 0.1 }
        )
      end
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
      json = JSON.parse(raw)
      JSON::Validator.validate!(PLAN_SCHEMA, json)
      json
    rescue JSON::ParserError, JSON::Schema::ValidationError => e
      context.tracer.event("plan_invalid_json", message: e.message, raw: raw)
      { "confidence" => 0.0, "summary" => "invalid plan", "actions" => [] }
    end

    def parse_review(raw)
      json = JSON.parse(raw)
      JSON::Validator.validate!(REVIEW_SCHEMA, json)
      json
    rescue JSON::ParserError, JSON::Schema::ValidationError => e
      context.tracer.event("plan_review_invalid", message: e.message, raw: raw)
      { "approved" => true, "issues" => [] }
    end

    def build_prompt(task, feedback)
      retrieved = context.index.retrieve(task, limit: 6).map do |snippet|
        "#{snippet["path"]}:\n#{snippet["text"]}\n---"
      end.join("\n")

      history = context.session_memory.last_turns(8).map do |turn|
        "#{turn["role"]}: #{turn["content"]}"
      end.join("\n")

      plugin_guidance = context.plugins.filter_map do |plugin|
        plugin.on_prompt(context, task) if plugin.respond_to?(:on_prompt)
      end.join("\n")

      tools = context.tool_registry.tools.values.map do |tool|
        "- #{tool.name}: #{tool.description}"
      end.join("\n")

      feedback_section = if feedback && !Array(feedback).empty?
                           "Known issues from reviewer:\n#{Array(feedback).join("\n")}"
                         else
                           ""
                         end

      <<~PROMPT
        #{Prompts::PLANNER_SYSTEM}

        #{plugin_guidance}

        Available tools:
        #{tools}

        Recent conversation:
        #{history}

        Repository context:
        #{retrieved}

        #{feedback_section}

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
