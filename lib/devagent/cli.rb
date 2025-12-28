# frozen_string_literal: true

require "thor"
require_relative "context"
require_relative "auto"
require_relative "orchestrator"
require_relative "diagnostics"
require_relative "ui"

module Devagent
  # CLI exposes Thor commands for launching the agent and running diagnostics.
  class CLI < Thor
    class_option :provider, type: :string, desc: "Provider override (auto|openai|ollama)"
    class_option :model, type: :string, desc: "Default model for general tasks"
    class_option :planner_model, type: :string, desc: "Planner model override"
    class_option :developer_model, type: :string, desc: "Developer model override"
    class_option :reviewer_model, type: :string, desc: "Reviewer/tester model override"
    class_option :embed_model, type: :string, desc: "Embedding model override"
    class_option :ollama_host, type: :string, desc: "Ollama server URL (overrides ENV and ~/.devagent.yml)"

    def self.exit_on_failure?
      true
    end

    # Default task: start the REPL when invoked without a subcommand
    # If a prompt is provided as an argument, execute it directly and exit
    desc "start [PROMPT]", "Start autonomous REPL (default) or execute a single prompt"
    def start(*args)
      ctx = build_context

      # If a prompt is provided, execute it directly and exit
      if args.any? && !args.first.nil? && !args.first.strip.empty?
        prompt = args.join(" ").strip
        ui = UI::Toolkit.new(output: $stdout, input: $stdin)
        orchestrator = Orchestrator.new(ctx, output: $stdout, ui: ui)
        begin
          orchestrator.run(prompt)
        rescue StandardError => e
          say("Error: #{e.message}", :red)
          exit 1
        end
        return
      end

      # Otherwise, start the REPL
      Auto.new(ctx, input: $stdin, output: $stdout).repl
    end

    desc "diag", "Print provider/model diagnostics"
    def diag
      ctx = build_context
      host, host_source = Devagent::Config.resolve_ollama_host(cli_host: options[:ollama_host])
      info = {
        provider: ctx.resolved_provider,
        ollama: {
          host: host,
          host_source: Devagent::Config.format_source(host_source)
        },
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
      say "  ollama host  : #{info[:ollama][:host]} (#{info[:ollama][:host_source]})"
      say "  models       : #{info[:models]}"
      say "  embedding    : #{info[:embedding]}"
      say "  OPENAI_API_KEY: #{info[:openai_key]}"
      info
    end

    desc "config", "Print resolved Devagent configuration"
    def config
      host, host_source = Devagent::Config.resolve_ollama_host(cli_host: options[:ollama_host])
      timeout, _timeout_source = Devagent::Config.resolve_ollama_timeout_seconds

      say "Devagent configuration:"
      say "  Ollama host   : #{host}"
      say "  Host source   : #{Devagent::Config.format_source(host_source)}"
      say "  Ollama timeout: #{timeout}s"
      say "  User config   : #{Devagent::Config::CONFIG_PATH}"
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
      overrides["ollama"] = { "host" => options[:ollama_host] } if options[:ollama_host]

      # If only --model is provided (without role-specific models), cascade it to all roles
      if options[:model] && !options[:planner_model] && !options[:developer_model] && !options[:reviewer_model]
        overrides["model"] = options[:model]
        overrides["planner_model"] = options[:model]
        overrides["developer_model"] = options[:model]
        overrides["reviewer_model"] = options[:model]
      else
        # Use explicit overrides if provided
        overrides["model"] = options[:model] if options[:model]
        overrides["planner_model"] = options[:planner_model] if options[:planner_model]
        overrides["developer_model"] = options[:developer_model] if options[:developer_model]
        overrides["reviewer_model"] = options[:reviewer_model] if options[:reviewer_model]
      end

      overrides["embed_model"] = options[:embed_model] if options[:embed_model]
      overrides
    end
  end
end
