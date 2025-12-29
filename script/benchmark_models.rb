# frozen_string_literal: true

require "json"
require "benchmark"
require "net/http"
require "uri"
require_relative "../lib/devagent/ollama"

DEFAULT_MODELS = [
  "qwen2.5-coder:7b-instruct",
  "llama3.1:8b-instruct",
  "deepseek-coder:6.7b-instruct",
  "mistral:7b-instruct"
].freeze

MODELS =
  ENV.fetch("MODELS", "").strip.empty? ? DEFAULT_MODELS : ENV.fetch("MODELS").split(",").map(&:strip).reject(&:empty?)

DEFAULT_PARAMS = {
  temperature: 0,
  top_p: 1,
  seed: 42
}.freeze

LATENCY_THRESHOLD_SECONDS = 2.5

BENCHMARKS = {
  json_schema: {
    prompt: <<~PROMPT,
      You are a planner.
      Output ONLY valid JSON matching the schema (no markdown, no commentary).
      Add a method sum(a, b) to lib/math.rb and write a test.
    PROMPT
    schema: {
      type: "object",
      properties: {
        steps: {
          type: "array",
          items: {
            type: "object",
            properties: {
              action: { type: "string" },
              path: { type: "string" }
            },
            required: ["action"]
          }
        }
      },
      required: ["steps"]
    }
  },

  diff_discipline: {
    prompt: <<~PROMPT
      Output ONLY a unified diff patch.
      Modify the following Ruby method to handle nil input safely.
      Keep the change minimal. Do not rewrite unrelated code.

      def foo(x)
        x + 1
      end
    PROMPT
  },

  stability: {
    prompt: <<~PROMPT
      You cannot run commands here.
      If you are blocked or lack required information, output exactly:
      BLOCKED
    PROMPT
  },

  latency: {
    prompt: "Explain Ruby blocks in one paragraph.",
    params: { num_predict: 140 }
  }
}.freeze

def schema_obedient?(json_text)
  obj = JSON.parse(json_text)
  return false unless obj.is_a?(Hash)
  return false unless obj["steps"].is_a?(Array)

  obj["steps"].all? do |step|
    next false unless step.is_a?(Hash)
    next false unless step["action"].is_a?(String) && !step["action"].empty?
    next false if step.key?("path") && !step["path"].is_a?(String)

    true
  end
rescue JSON::ParserError
  false
end

def diff_disciplined?(text)
  lines = text.lines
  return false if lines.empty?
  return false if lines.count > 60

  has_headers = text.match?(/^(diff --git|---\s)/)
  has_hunk = text.match?(/^@@/m)
  return false unless has_headers && has_hunk

  changed = lines.count { |l| (l.start_with?("+") || l.start_with?("-")) && !l.start_with?("+++") && !l.start_with?("---") }
  changed <= 10
end

def stable_non_hallucinating?(text)
  text.strip == "BLOCKED"
end

ollama_host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")

begin
  uri = URI(ollama_host)
  tags_uri = URI.join(uri.to_s, "/api/tags")
  res = Net::HTTP.get_response(tags_uri)
  unless res.is_a?(Net::HTTPSuccess)
    warn "ERROR: Ollama is not responding at #{ollama_host} (GET /api/tags -> #{res.code})"
    exit 2
  end
rescue StandardError => e
  warn "ERROR: Ollama is unreachable at #{ollama_host} (#{e.class}: #{e.message})"
  exit 2
end

client = Devagent::Ollama::Client.new("host" => ollama_host)
results = {}

MODELS.each do |model|
  puts "\nBenchmarking #{model}"

  score = {
    json_schema: 0,
    diff_discipline: 0,
    stability: 0,
    latency: 0,
    errors: {}
  }

  # 1) JSON / schema obedience
  begin
    res = client.generate(
      model: model,
      prompt: BENCHMARKS[:json_schema][:prompt],
      params: DEFAULT_PARAMS,
      format: BENCHMARKS[:json_schema][:schema]
    )
    score[:json_schema] = schema_obedient?(res) ? 1 : 0
  rescue StandardError
    score[:json_schema] = 0
    score[:errors][:json_schema] = "request_failed"
  end

  # 2) Diff discipline
  begin
    res = client.generate(
      model: model,
      prompt: BENCHMARKS[:diff_discipline][:prompt],
      params: DEFAULT_PARAMS.merge(num_predict: 220)
    )
    score[:diff_discipline] = diff_disciplined?(res) ? 1 : 0
  rescue StandardError
    score[:diff_discipline] = 0
    score[:errors][:diff_discipline] = "request_failed"
  end

  # 3) Stability / hallucination resistance
  begin
    res = client.generate(
      model: model,
      prompt: BENCHMARKS[:stability][:prompt],
      params: DEFAULT_PARAMS.merge(num_predict: 16)
    )
    score[:stability] = stable_non_hallucinating?(res) ? 1 : 0
  rescue StandardError
    score[:stability] = 0
    score[:errors][:stability] = "request_failed"
  end

  # 4) Latency (local usability)
  begin
    time = Benchmark.realtime do
      client.generate(
        model: model,
        prompt: BENCHMARKS[:latency][:prompt],
        params: DEFAULT_PARAMS.merge(BENCHMARKS[:latency][:params] || {})
      )
    end
    score[:latency] = time < LATENCY_THRESHOLD_SECONDS ? 1 : 0
    score[:latency_seconds] = time.round(3)
  rescue StandardError
    score[:latency] = 0
    score[:latency_seconds] = nil
    score[:errors][:latency] = "request_failed"
  end

  score[:total] = score.values_at(:json_schema, :diff_discipline, :stability, :latency).sum
  results[model] = score
end

puts "\nDevagent Model Benchmark Results"
puts JSON.pretty_generate(results)

