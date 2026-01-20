# frozen_string_literal: true

require "json"
require "json-schema"
require_relative "prompts"

module Devagent
  # IntentClassifier decides whether a request needs the agent/tooling loop.
  #
  # Controller-owned routing:
  # - EXPLANATION/GENERAL => no tools, no repo indexing
  # - CODE_EDIT/DEBUG/CODE_REVIEW => run phased agent loop
  class IntentClassifier
    INTENT_SCHEMA = {
      "type" => "object",
      "required" => %w[intent confidence],
      "properties" => {
        "intent" => {
          "type" => "string",
          "enum" => %w[CODE_EDIT CODE_REVIEW EXPLANATION DEBUG GENERAL REJECT]
        },
        "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
      }
    }.freeze

    def initialize(context)
      @context = context
    end

    def classify(task)
      # In test doubles / minimal contexts, fall back to deterministic heuristics.
      return heuristic(task) unless context.respond_to?(:query) && context.respond_to?(:provider_for)

      prompt = <<~PROMPT
        #{Prompts::INTENT_SYSTEM}

        Task:
        #{task}
      PROMPT

      response_format = json_schema_format(INTENT_SCHEMA) if context.provider_for(:developer) == "openai"
      raw = context.query(
        role: :developer,
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

      # Try to extract just the JSON object if there's extra text after it
      json_match = cleaned.match(/\{.*\}/m)
      json_text = json_match ? json_match[0] : cleaned

      parsed = JSON.parse(json_text)
      JSON::Validator.validate!(INTENT_SCHEMA, parsed)
      parsed
    rescue StandardError => e
      context.tracer.event("intent_classification_failed", message: e.message) if context.respond_to?(:tracer)
      heuristic(task)
    end

    private

    attr_reader :context

    def heuristic(task)
      text = task.to_s.strip.downcase
      return { "intent" => "REJECT", "confidence" => 0.9 } if text.empty?

      explanation_starts = %w[what who when where why how explain describe summarize]
      code_action = %w[add create update implement refactor fix write generate run install build change edit remove
                       delete]
      debug_words = %w[error exception failing failed stacktrace stack trace bug]
      review_words = %w[review critique audit assess]

      return { "intent" => "DEBUG", "confidence" => 0.7 } if debug_words.any? { |w| text.include?(w) }
      return { "intent" => "CODE_REVIEW", "confidence" => 0.7 } if review_words.any? { |w| text.include?(w) }
      return { "intent" => "CODE_EDIT", "confidence" => 0.75 } if code_action.any? do |w|
        text.start_with?(w) || text.include?(" #{w} ")
      end
      return { "intent" => "EXPLANATION", "confidence" => 0.7 } if text.end_with?("?") || explanation_starts.any? do |w|
        text.start_with?("#{w} ")
      end

      { "intent" => "GENERAL", "confidence" => 0.55 }
    end

    def json_schema_format(schema)
      {
        type: "json_schema",
        json_schema: {
          name: "devagent_intent_schema",
          schema: schema
        }
      }
    end
  end
end
