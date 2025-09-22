# frozen_string_literal: true

require "thor"
require_relative "context"
require_relative "auto"

module Devagent
  class CLI < Thor
    desc "start", "Start autonomous REPL (default)"
    def start
      ctx = Context.build(Dir.pwd)
      Auto.new(ctx).repl
    end

    default_task :start
  end
end
