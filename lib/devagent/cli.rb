# frozen_string_literal: true

require "thor"
require "paint"
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

    desc "console", "Start an interactive chat console session with Ollama"
    method_option :model,
                  aliases: "-m",
                  default: "deepseek-coder:6.7b",
                  desc: "The model to use (must be available in Ollama)"
    def console
      say Paint["Starting interactive session with Ollama (model: #{options[:model]})", :yellow]
      session = Chat::Session.new(model: options[:model], input: $stdin, output: $stdout)
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
  end
end
