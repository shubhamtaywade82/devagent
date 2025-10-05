#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "devagent"
require "json"
require "devagent/context"
require "devagent/llm"

ctx = Devagent::Context.build(Dir.pwd)
puts "Provider: #{ctx.resolved_provider}"
puts "Planner model: #{ctx.model_for(:planner)}"
puts "Developer model: #{ctx.model_for(:developer)}"
puts "Reviewer model: #{ctx.model_for(:reviewer)}"
puts "Embedding backend: #{ctx.embedding_backend_info.inspect}"

adapter = ctx.llm_for(:planner)
prompt = "Respond with a JSON object {\"status\":\"ok\"}."

begin
  response = adapter.query(prompt, response_format: { type: "json_object" })
  puts "LLM response: #{response}"
rescue Devagent::Error => e
  warn "LLM call failed: #{e.message}"
  exit 1
rescue StandardError => e
  warn "Unexpected error during LLM smoke test: #{e.message}"
  exit 1
end
