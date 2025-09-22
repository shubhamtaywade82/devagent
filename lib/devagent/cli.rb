# frozen_string_literal: true

require "thor"
require_relative "context"
require_relative "auto"
require_relative "diagnostics"

module Devagent
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "start", "Start autonomous REPL (default)"
    def start
      ctx = Context.build(Dir.pwd)
      Auto.new(ctx, input: $stdin, output: $stdout).repl
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
