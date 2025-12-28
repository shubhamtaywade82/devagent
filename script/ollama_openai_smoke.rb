#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/devagent/context"
require_relative "../lib/devagent/llm"

repo_root = File.expand_path("..", __dir__)
context = Devagent::Context.build(repo_root)
adapter = context.llm_for(:planner)

puts "== Non-streaming =="
puts adapter.query("Write a Ruby method that safely parses a CSV string.")

puts "\n== Streaming =="
buffer = +""
adapter.stream("Explain Ruby blocks in 3 bullet points.") do |token|
  next if token.nil? || token.empty?

  print token
  buffer << token
end
puts
