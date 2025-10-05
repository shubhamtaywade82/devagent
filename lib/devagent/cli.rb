# frozen_string_literal: true

require "thor"
require_relative "context"
require_relative "auto"
require_relative "diagnostics"

module Devagent
  # CLI exposes Thor commands for launching the agent and running diagnostics.
  class CLI < Thor
    class_option :provider, type: :string, desc: "Provider override (auto|openai|ollama)"
    class_option :model, type: :string, desc: "Default model for general tasks"
    class_option :planner_model, type: :string, desc: "Planner model override"
    class_option :developer_model, type: :string, desc: "Developer model override"
    class_option :reviewer_model, type: :string, desc: "Reviewer/tester model override"
    class_option :embed_model, type: :string, desc: "Embedding model override"

    def self.exit_on_failure?
      true
    end

    # Default task: start the REPL when invoked without a subcommand
    desc "start", "Start autonomous REPL (default)"
    def start(*_args)
      ctx = build_context
      Auto.new(ctx, input: $stdin, output: $stdout).repl
    end

    desc "diag", "Print provider/model diagnostics"
    def diag
      ctx = build_context
      info = {
        provider: ctx.resolved_provider,
        models: {
          default: ctx.model_for(:default),
          planner: ctx.model_for(:planner),
          developer: ctx.model_for(:developer),
          reviewer: ctx.model_for(:reviewer)
        },
        embedding: ctx.embedding_backend_info.merge("dim" => ctx.index.metadata["dim"]),
        openai_key: ctx.openai_available? ? "set" : "missing"
      }
      say "Devagent diagnostics"
      say "  provider     : #{info[:provider]}"
      say "  models       : #{info[:models]}"
      say "  embedding    : #{info[:embedding]}"
      say "  OPENAI_API_KEY: #{info[:openai_key]}"
      info
    end

    desc "test", "Run diagnostics to verify configuration and connectivity"
    def test
      ctx = build_context
      diagnostics = Diagnostics.new(ctx, output: $stdout)
      success = diagnostics.run
      raise Thor::Error, "Diagnostics failed" unless success

      success
    end

    default_task :start

    private

    def build_context
      Context.build(Dir.pwd, context_overrides)
    end

    def context_overrides
      overrides = {}
      overrides["provider"] = options[:provider] if options[:provider]
      overrides["model"] = options[:model] if options[:model]
      overrides["planner_model"] = options[:planner_model] if options[:planner_model]
      overrides["developer_model"] = options[:developer_model] if options[:developer_model]
      overrides["reviewer_model"] = options[:reviewer_model] if options[:reviewer_model]
      overrides["embed_model"] = options[:embed_model] if options[:embed_model]
      overrides
    end
  end
end
