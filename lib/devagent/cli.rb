# frozen_string_literal: true

require "thor"
require_relative "context"
require_relative "auto"

module Devagent
  # Minimal CLI: start Q&A REPL.
  class CLI < Thor
    def self.exit_on_failure? = true

    desc "start", "Start Q&A REPL (default)"
    def start
      ctx = Context.build(Dir.pwd)
      Auto.new(ctx, input: $stdin, output: $stdout).repl
    end

    default_task :start
  end
end
