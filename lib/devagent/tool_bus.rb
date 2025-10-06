# frozen_string_literal: true

require "diffy"
require "English"
require "fileutils"
require_relative "safety"
require_relative "util"

module Devagent
  # ToolBus executes validated tool actions with safety checks and tracing.
  class ToolBus
    attr_reader :context, :registry, :safety

    def initialize(context, registry:)
      @context = context
      @registry = registry
      @safety = Safety.new(context)
      @changes_made = false
    end

    def invoke(action)
      name = action.fetch("type")
      args = action.fetch("args", {})
      tool = registry.validate!(name, args)
      send(tool.handler, args)
    rescue StandardError => e
      context.tracer.event("tool_error", tool: name, message: e.message)
      raise
    end

    def reset!
      @changes_made = false
    end

    def changes_made?
      @changes_made
    end

    def write_file(args)
      relative_path = args.fetch("path")
      content = args.fetch("content")
      guard_path!(relative_path)
      context.tracer.event("write_file", path: relative_path)
      full = File.join(context.repo_path, relative_path)
      FileUtils.mkdir_p(File.dirname(full))
      original = File.exist?(full) ? File.read(full, encoding: "UTF-8") : ""
      diff = Diffy::Diff.new(original, content, context: 3).to_s(:text)
      context.tracer.event("diff", path: relative_path, diff: diff)
      return content if dry_run?

      File.write(full, content)
      @changes_made = true
      content
    end

    def apply_patch(args)
      patch = args.fetch("patch")
      context.tracer.event("git_apply", patch: patch)
      return patch if dry_run?

      return :skipped unless git_repo?

      IO.popen(["git", "-C", context.repo_path, "apply", "--whitespace=nowarn", "-"], "w") { |io| io.write(patch) }
      raise Error, "git apply failed" unless $CHILD_STATUS&.success?

      @changes_made = true
      patch
    end

    def run_tests(args)
      command = args["command"] || default_test_command
      context.tracer.event("run_tests", command: command)
      return :skipped if dry_run?

      Util.run!(command, chdir: context.repo_path)
      :ok
    end

    def run_command(args)
      command = args.fetch("command")
      context.tracer.event("run_command", command: command)
      return "skipped" if dry_run?

      Util.run!(command, chdir: context.repo_path)
    end

    private

    def guard_path!(relative_path)
      raise Error, "path required" if relative_path.to_s.empty?
      raise Error, "path not allowed: #{relative_path}" unless safety.allowed?(relative_path)
    end

    def git_repo?
      File.directory?(File.join(context.repo_path, ".git"))
    end

    def dry_run?
      context.config.dig("auto", "dry_run") == true
    end

    def default_test_command
      context.plugins.filter_map do |plugin|
        plugin.respond_to?(:test_command) ? plugin.test_command(context) : nil
      end.first || "bundle exec rspec"
    end
  end
end
