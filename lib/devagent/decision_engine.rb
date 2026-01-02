# frozen_string_literal: true

require "json"
require "json-schema"
require_relative "prompts"

module Devagent
  # DecisionEngine determines whether we are done, should retry, or are blocked.
  class DecisionEngine
    DECISION_SCHEMA = {
      "type" => "object",
      "required" => %w[decision reason confidence],
      "properties" => {
        "decision" => { "type" => "string", "enum" => %w[SUCCESS RETRY BLOCKED] },
        "reason" => { "type" => "string" },
        "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
      }
    }.freeze

    def initialize(context)
      @context = context
    end

    def decide(plan:, step_results:, observations:)
      return heuristic(plan: plan, observations: observations) unless context.respond_to?(:query) && context.respond_to?(:provider_for)

      prompt = <<~PROMPT
        #{Prompts::DECISION_SYSTEM}

        Plan:
        #{JSON.pretty_generate(plan)}

        Step results:
        #{JSON.pretty_generate(step_results)}

        Observations:
        #{JSON.pretty_generate(observations)}
      PROMPT

      response_format = json_schema_format(DECISION_SCHEMA) if context.provider_for(:reviewer) == "openai"
      raw = context.query(
        role: :reviewer,
        prompt: prompt,
        stream: false,
        response_format: response_format,
        params: { temperature: 0.0 }
      )

      # Strip markdown code blocks if present
      cleaned = raw.to_s
                   .gsub(/^```(?:json|ruby|javascript|typescript|python|java|go|rust|php|markdown|yaml|text)?\s*\n/, "")
                   .gsub(/\n```\s*$/, "")
                   .strip

      # Try to extract just the JSON object if there's extra text before/after it
      json_match = cleaned.match(/\{.*\}/m)
      json_text = json_match ? json_match[0] : cleaned

      parsed = JSON.parse(json_text)
      JSON::Validator.validate!(DECISION_SCHEMA, parsed)
      parsed
    rescue StandardError => e
      context.tracer.event("decision_failed", message: e.message) if context.respond_to?(:tracer)
      heuristic(plan: plan, observations: observations)
    end

    private

    attr_reader :context

    def heuristic(plan:, observations:)
      if observations.any? { |o| o["type"] == "TEST_RESULT" && o["status"] == "FAIL" }
        return { "decision" => "RETRY", "reason" => "Tests failing", "confidence" => 0.65 }
      end

      if Array(plan["success_criteria"]).empty?
        return { "decision" => "SUCCESS", "reason" => "No success criteria provided; assuming done", "confidence" => 0.55 }
      end

      if observations.any? { |o| o["type"] == "TEST_RESULT" && o["status"] == "PASS" }
        return { "decision" => "SUCCESS", "reason" => "Tests passed", "confidence" => 0.85 }
      end

      { "decision" => "RETRY", "reason" => "Uncertain; refine plan", "confidence" => 0.55 }
    end

    def json_schema_format(schema)
      {
        type: "json_schema",
        json_schema: {
          name: "devagent_decision_schema",
          schema: schema
        }
      }
    end
  end
end

