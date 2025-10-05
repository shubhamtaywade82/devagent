# frozen_string_literal: true

require "json"
require "json-schema"
require_relative "prompts"

module Devagent
  Plan = Struct.new(:summary, :actions, :confidence, keyword_init: true)

  # Planner coordinates with the planning model to produce validated actions.
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

    def initialize(context)
      @context = context
    end

    def plan(task)
      prompt = build_prompt(task)
      raw = context.planner(prompt)
      payload = parse_plan(raw)
      Plan.new(
        summary: payload["summary"],
        actions: payload["actions"] || [],
        confidence: payload["confidence"].to_f
      )
    rescue StandardError => e
      context.tracer.event("planner_error", message: e.message)
      Plan.new(summary: "planning failed", actions: [], confidence: 0.0)
    end

    private

    attr_reader :context

    def build_prompt(task)
      retrieved = context.index.search(task, k: 6).map do |snippet|
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

      <<~PROMPT
        #{Prompts::PLANNER_SYSTEM}

        #{plugin_guidance}

        Available tools:
        #{tools}

        Recent conversation:
        #{history}

        Repository context:
        #{retrieved}

        Task:
        #{task}

        Output strictly valid JSON.
      PROMPT
    end

    def parse_plan(raw)
      json = JSON.parse(raw)
      JSON::Validator.validate!(PLAN_SCHEMA, json)
      json
    rescue JSON::ParserError, JSON::Schema::ValidationError
      { "confidence" => 0.0, "actions" => [] }
    end
  end
end
