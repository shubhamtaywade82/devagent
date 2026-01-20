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

      # Show model selection if verbose or if models differ from defaults
      if options[:model] || options[:planner_model] || options[:developer_model] || options[:reviewer_model]
        say("Using models:", :green)
        say("  Default: #{ctx.model_for(:default)}", :cyan)
        say("  Planner: #{ctx.model_for(:planner)}", :cyan)
        say("  Developer: #{ctx.model_for(:developer)}", :cyan)
        say("  Reviewer: #{ctx.model_for(:reviewer)}", :cyan)
        say("")
      end

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

    desc "index SUBCOMMAND", "Manage the embedding index"
    def index(subcommand = "status")
      ctx = build_context

      case subcommand.downcase
      when "status"
        index_status(ctx)
      when "build"
        index_build(ctx)
      when "rebuild"
        index_rebuild(ctx)
      when "stale"
        index_stale(ctx)
      else
        say("Unknown subcommand: #{subcommand}. Use: status, build, rebuild, stale", :red)
      end
    end

    default_task :start

    private

    def index_status(ctx)
      require_relative "retrieval_controller"

      controller = RetrievalController.new(ctx)
      status = controller.index_status

      say("Embedding Index Status", :green)
      say("-" * 40)
      say("  Document count    : #{status[:document_count]}")
      say("  Repository empty  : #{status[:repo_empty] ? "Yes" : "No"}")
      say("  Embeddings ready  : #{status[:embeddings_ready] ? "Yes" : "No"}")
      say("  Embeddings stale  : #{status[:embeddings_stale] ? "Yes (rebuild recommended)" : "No"}")
      say("")
      say("Backend:", :cyan)
      say("  Provider          : #{status[:backend]["provider"]}")
      say("  Model             : #{status[:backend]["model"]}")
      say("")

      if status[:metadata].any?
        say("Metadata:", :cyan)
        say("  Dimension         : #{status[:metadata]["dim"]}")
        say("  Indexed at        : #{status[:metadata]["indexed_at"] || "unknown"}")
        say("  Stored provider   : #{status[:metadata]["provider"]}")
        say("  Stored model      : #{status[:metadata]["model"]}")
      else
        say("Metadata: (none - index not built)", :yellow)
      end

      # Check for stale files
      stale_count = ctx.index.stale_files.size
      return unless stale_count.positive?

      say("")
      say("Stale files: #{stale_count} (run 'devagent index build' to update)", :yellow)
    end

    def index_build(ctx)
      say("Building embedding index (incremental)...", :cyan)
      stale_before = ctx.index.stale_files.size

      if stale_before.zero? && ctx.index.document_count.positive?
        say("Index is up to date. No changes needed.", :green)
        return
      end

      result = ctx.index.build_incremental!
      say("Indexed #{result.size} chunks from #{stale_before} files.", :green)
    end

    def index_rebuild(ctx)
      say("Rebuilding embedding index (full)...", :cyan)
      ctx.index.store.clear!
      result = ctx.index.build!
      say("Indexed #{result.size} chunks.", :green)
    end

    def index_stale(ctx)
      stale = ctx.index.stale_files
      if stale.empty?
        say("No stale files. Index is up to date.", :green)
      else
        say("Stale files (#{stale.size}):", :yellow)
        stale.first(20).each { |f| say("  - #{f}") }
        say("  ... and #{stale.size - 20} more") if stale.size > 20
      end
    end

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
