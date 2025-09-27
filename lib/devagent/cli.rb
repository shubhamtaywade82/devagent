# frozen_string_literal: true

require "fileutils"
require "thor"
require "paint"
require "tty-box"
require "tty-config"
require "tty-logger"
require "tty-prompt"
require_relative "context"
require_relative "auto"
require_relative "diagnostics"
require_relative "chat/session"

module Devagent
  # CLI exposes Thor commands for launching the agent and running diagnostics.
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "start", "Start autonomous REPL (default)"
    def start
      ctx = Context.build(Dir.pwd)
      Auto.new(ctx, input: $stdin, output: $stdout).repl
    end

    DEFAULT_MODEL = "deepseek-coder:6.7b"
    CONFIG_DIR = File.expand_path("~/.config/devagent")

    class_option :verbose, type: :boolean, desc: "Enable verbose logging"

    desc "console", "Start an interactive chat console session with Ollama"
    method_option :model,
                  aliases: "-m",
                  type: :string,
                  desc: "The model to use (leave blank to use saved default or prompt)"
    method_option :save_model,
                  type: :boolean,
                  default: false,
                  desc: "Persist the chosen model to ~/.config/devagent/config.yml"
    def console
      prompt = TTY::Prompt.new(enable_color: true)
      model = resolve_model_option(options[:model], prompt)

      save_default_model(model) if options[:save_model]

      say TTY::Box.frame(
        "Starting interactive session with Ollama\nModel: #{model}",
        align: :center,
        padding: 1,
        title: { top_left: "Devagent" }
      )

      session = Chat::Session.new(
        model: model,
        input: $stdin,
        output: $stdout,
        logger: build_logger(options[:verbose])
      )
      session.start
    end

    desc "test", "Run diagnostics to verify configuration and Ollama connectivity"
    def test
      ctx = Context.build(Dir.pwd)
      diagnostics = Diagnostics.new(ctx, output: $stdout)
      success = diagnostics.run
      raise Thor::Error, "Diagnostics failed" unless success

      success
    end

    default_task :start

    no_commands do
      def resolve_model_option(option_value, prompt)
        trimmed = option_value.to_s.strip
        return trimmed unless trimmed.empty?

        stored = if config.respond_to?(:key?) && config.key?(:defaults, :model)
                   config.fetch(:defaults, :model)
                 end
        default_choice = stored.to_s.empty? ? DEFAULT_MODEL : stored

        interactive = prompt.respond_to?(:input) ? prompt.input.tty? : $stdin.tty?
        return default_choice unless interactive

        prompt.ask("Select Ollama model:", default: default_choice) do |q|
          q.modify :strip
          q.required true
        end
      end

      def save_default_model(model)
        FileUtils.mkdir_p(CONFIG_DIR)
        config.set(:defaults, :model, model)
        config.write(force: true)
        say Paint["Saved default model to #{CONFIG_DIR}/config.yml", :green]
      end

      def config
        return @config if defined?(@config)

        cfg = TTY::Config.new
        cfg.append_path(CONFIG_DIR)
        cfg.filename = "config"
        cfg.extname = ".yml"
        cfg.read if cfg.exist?
        @config = cfg
      end

      def build_logger(verbose_flag)
        enable_verbose = verbose_flag || ENV.fetch("DEVAGENT_VERBOSE", nil)&.match?(/^(1|true|yes)$/i)
        return nil unless enable_verbose

        if defined?(@logger) && @logger
          @logger.level = :debug
          return @logger
        end

        @logger = TTY::Logger.new(output: $stdout) do |logger|
          logger.level = :debug
        end
      end
    end
  end
end
