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

    def read_file(args)
      relative_path = args.fetch("path")
      guard_path!(relative_path)
      full = File.join(context.repo_path, relative_path)
      context.tracer.event("read_file", path: relative_path)
      return "" unless File.exist?(full)

      File.read(full, encoding: "UTF-8")
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

    def write_diff(args)
      relative_path = args.fetch("path")
      diff = args.fetch("diff")
      guard_path!(relative_path)
      validate_diff!(relative_path, diff)

      context.tracer.event("fs_write_diff", path: relative_path)
      return diff if dry_run?

      # We intentionally use git apply because it is the most reliable diff applier
      # for unified diffs and keeps behavior deterministic.
      IO.popen(["git", "-C", context.repo_path, "apply", "--whitespace=nowarn", "-"], "w") { |io| io.write(diff) }
      raise Error, "diff apply failed" unless $CHILD_STATUS&.success?

      @changes_made = true
      diff
    end

    def delete_file(args)
      relative_path = args.fetch("path")
      guard_path!(relative_path)
      context.tracer.event("fs_delete", path: relative_path)
      return :skipped if dry_run?

      full = File.join(context.repo_path, relative_path)
      FileUtils.rm_f(full)
      @changes_made = true
      :ok
    end

    def run_tests(args)
      command = args["command"] || default_test_command
      context.tracer.event("run_tests", command: command)
      return :skipped if dry_run?
      raise Error, "command not allowed" unless command_allowed?(command)

      Util.run!(command, chdir: context.repo_path)
      :ok
    end

    def check_command_help(args)
      command = args.fetch("command")
      # Extract base command (before any flags or help flags)
      # Remove common help flags if present
      base_cmd = command.split.reject { |part| %w[--help -h help].include?(part) }.first || command.split.first || command

      context.tracer.event("check_command_help", command: base_cmd)
      return "skipped" if dry_run?
      raise Error, "command not allowed" unless command_allowed?(base_cmd)

      # Try --help first, fall back to -h if that fails
      help_output = nil
      ["--help", "-h", "help"].each do |help_flag|
        begin
          help_command = "#{base_cmd} #{help_flag}"
          help_output = Util.run!(help_command, chdir: context.repo_path)
          break
        rescue StandardError => e
          # Try next help flag
          next
        end
      end

      raise Error, "Could not get help for command: #{base_cmd}. Command may not support --help, -h, or help flags." if help_output.nil?

      help_output
    end

    def run_command(args)
      command = args.fetch("command")
      context.tracer.event("run_command", command: command)
      return "skipped" if dry_run?
      raise Error, "command not allowed" unless command_allowed?(command)

      # For certain commands (like rubocop, linters), non-zero exit codes
      # indicate issues found, not execution failure. Capture output regardless.
      if command_returns_meaningful_output_on_nonzero?(command)
        result = Util.run_capture(command, chdir: context.repo_path)
        # Return structured result that includes output even on non-zero exit
        {
          "stdout" => result["stdout"],
          "stderr" => result["stderr"],
          "exit_code" => result["exit_code"],
          "success" => true # Mark as success since we got output
        }
      else
        # For other commands, use strict mode (fail on non-zero)
        output = Util.run!(command, chdir: context.repo_path)
        {
          "stdout" => output,
          "stderr" => "",
          "exit_code" => 0,
          "success" => true
        }
      end
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

    def command_returns_meaningful_output_on_nonzero?(command)
      # Commands that return non-zero exit codes to indicate issues found,
      # but still produce valid output that should be analyzed
      cmd = command.to_s.strip.downcase
      %w[rubocop eslint flake8 pylint shellcheck].any? { |tool| cmd.include?(tool) }
    end

    def command_allowed?(command)
      cmd = command.to_s.strip
      return false if cmd.empty?

      deny_patterns = [
        /\Agit\s+push\b/i,
        /\Agit\s+commit\b/i,
        /\Agit\s+reset\b/i,
        /\Agit\s+clean\b/i,
        /\Arm\s+/i,
        /\Asudo\b/i
      ]
      return false if deny_patterns.any? { |re| cmd.match?(re) }

      allow = Array(context.config.dig("auto", "command_allowlist"))
      # Back-compat: nil/empty allowlist means allow any command.
      return true if allow.empty?

      allow.any? { |prefix| cmd.start_with?(prefix.to_s) }
    end

    def validate_diff!(path, diff)
      lines = diff.to_s.lines
      raise Error, "diff too large" if lines.count > 200
      raise Error, "diff missing hunk context" unless diff.include?("@@")
      expected = "--- a/#{path}"
      raise Error, "path mismatch in diff" unless diff.to_s.start_with?(expected)
    end
  end
end
