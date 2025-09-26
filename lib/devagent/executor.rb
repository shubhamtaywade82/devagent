# frozen_string_literal: true

require "fileutils"
require_relative "safety"
require_relative "util"

module Devagent
  class Executor
    attr_reader :log

    def initialize(ctx)
      @ctx = ctx
      @repo = ctx.repo_path
      @safety = Safety.new(ctx)
      @log = []
      @changed = false
    end

    def apply(actions)
      Array(actions).each { |action| apply_action(action) }
    end

    def changes_made?
      @changed
    end

    private

    def apply_action(action)
      type = action["type"]
      case type
      when "create_file"
        create_file(action["path"], action["content"] || "")
      when "edit_file"
        edit_file(action["path"], action.fetch("content"))
      when "run_command"
        run_command(action.fetch("command"))
      else
        @log << "Unknown action: #{action.inspect}"
      end
    end

    def create_file(rel, content)
      guard!(rel)
      @log << "create_file #{rel}"
      abs = File.join(@repo, rel)
      FileUtils.mkdir_p(File.dirname(abs))
      File.write(abs, content)
      @changed = true
    end

    def edit_file(rel, content)
      guard!(rel)
      @log << "edit_file #{rel}"
      abs = File.join(@repo, rel)
      FileUtils.mkdir_p(File.dirname(abs))
      File.write(abs, content)
      @changed = true
    end

    def run_command(cmd)
      @log << "run: #{cmd}"
      if command =~ /(^|\s)(>|>>)\s/ || command.include?("<<") || command =~ /\btee\b/
        raise "run_command forbids writing files via shell redirection. Use create_file/edit_file actions instead."
      end
      Util.run!(command, chdir: @repo)
    end

    def guard!(rel)
      raise "path required" if rel.to_s.empty?
      raise "path not allowed: #{rel}" unless @safety.allowed?(rel)
    end
  end
end
