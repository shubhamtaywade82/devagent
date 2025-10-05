#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require "yaml"
require "pathname"

ROOT = Pathname.new(File.expand_path("..", __dir__))

def ok(message)
  puts("✅ #{message}")
  true
end

def warn(message)
  puts("⚠️  #{message}")
  false
end

def bad(message)
  puts("❌ #{message}")
  false
end

def have_files?(*paths)
  missing = paths.reject { |path| ROOT.join(path).exist? }
  return ok("Files present: #{paths.join(", ")}") if missing.empty?

  bad("Missing files: #{missing.join(", ")}")
end

def load_yaml(path)
  YAML.load_file(ROOT.join(path))
rescue Errno::ENOENT
  bad("Missing YAML file: #{path}")
  nil
rescue Psych::SyntaxError => e
  bad("Failed to parse YAML #{path}: #{e.message}")
  nil
end

def check_provider_config
  config = load_yaml(".devagent.yml") || {}
  keys = %w[provider model planner_model developer_model reviewer_model embed_model]
  missing = keys.reject { |key| config.key?(key) }
  if missing.empty?
    ok("Core model keys present in .devagent.yml")
  else
    warn(".devagent.yml missing keys: #{missing.join(", ")}")
  end
end

def check_llm_adapters
  have_files?("lib/devagent/ollama.rb", "lib/devagent/llm.rb", "lib/devagent/llm/openai_adapter.rb")
end

def check_embeddings_meta
  path = ROOT.join("lib/devagent/embedding_index.rb")
  return bad("Missing embedding index implementation") unless path.exist?

  contents = path.read
  if contents.include?("embeddings.meta.json")
    ok("Embedding index tracks backend metadata")
  else
    warn("Embedding index missing backend metadata guard")
  end
end

def check_tooling
  files = %w[lib/devagent/tool_bus.rb lib/devagent/tool_registry.rb lib/devagent/safety.rb]
  have_files?(*files)
end

def check_prompts
  have_files?("lib/devagent/prompts.rb")
end

def check_orchestrator
  have_files?("lib/devagent/orchestrator.rb", "lib/devagent/planner.rb")
end

def check_memory_streaming
  mem = ROOT.join("lib/devagent/session_memory.rb").exist?
  stream = ROOT.join("lib/devagent/streamer.rb").exist?
  mem && stream ? ok("Session memory and streaming present") : warn("Missing session memory and/or streaming module")
end

def check_cli
  exe = ROOT.join("exe/devagent").exist?
  cli = ROOT.join("lib/devagent/cli.rb").exist?
  exe || cli ? ok("CLI entrypoints available") : bad("Missing CLI entrypoint (exe/devagent or lib/devagent/cli.rb)")
end

def check_specs
  specs = Dir[ROOT.join("spec/**/*_spec.rb")]
  specs.any? ? ok("RSpec specs detected (#{specs.size})") : warn("No RSpec specs found")
end

def check_git_safety
  files = Dir[ROOT.join("lib/devagent/**/*.rb")]
  safe = files.any? { |file| File.read(file).include?(".git/") }
  safe ? ok("Safety rules reference .git denylist") : warn("No explicit .git deny guard detected")
end

# Optional coverage check

def check_test_coverage
  last_run = ROOT.join("coverage/.last_run.json")
  return warn("Coverage report not found. Run specs to generate SimpleCov data.") unless last_run.exist?

  data = JSON.parse(last_run.read)
  covered = data.dig("result", "covered_percent") || data.dig("result", "line")
  return warn("Coverage percentage missing from report.") unless covered

  message = format("SimpleCov coverage: %.2f%%", covered)
  covered >= 80 ? ok(message) : bad(message)
rescue JSON::ParserError => e
  bad("Failed to parse coverage report: #{e.message}")
end

def run_audit
  puts "DevAgent Audit — #{Time.now.iso8601}"
  have_files?(".devagent.yml", "devagent.gemspec")
  check_provider_config
  check_llm_adapters
  check_embeddings_meta
  check_tooling
  check_prompts
  check_orchestrator
  check_memory_streaming
  check_cli
  check_specs
  check_git_safety
  check_test_coverage
end

run_audit
