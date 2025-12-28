# frozen_string_literal: true

require "diffy"
require "English"
require "fileutils"
require "json"
require "json-schema"
require "timeout"
require_relative "safety"
require_relative "util"
require_relative "prompts"

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
      content = File.exist?(full) ? File.read(full, encoding: "UTF-8") : ""

      { "path" => relative_path, "content" => content }
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
      return({ "applied" => false }) if dry_run?

      # We intentionally use git apply because it is the most reliable diff applier
      # for unified diffs and keeps behavior deterministic.
      IO.popen(["git", "-C", context.repo_path, "apply", "--whitespace=nowarn", "-"], "w") { |io| io.write(diff) }
      raise Error, "diff apply failed" unless $CHILD_STATUS&.success?

      @changes_made = true
      { "applied" => true }
    end

    def delete_file(args)
      relative_path = args.fetch("path")
      guard_path!(relative_path)
      context.tracer.event("fs_delete", path: relative_path)
      return({ "ok" => false }) if dry_run?

      full = File.join(context.repo_path, relative_path)
      FileUtils.rm_f(full)
      @changes_made = true
      { "ok" => true }
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
      return({ "stdout" => "", "stderr" => "", "exit_code" => 0 }) if dry_run?
      raise Error, "command not allowed" unless command_allowed?(command)

      timeout_s = (context.config.dig("auto", "command_timeout_seconds") || 60).to_i
      max_bytes = (context.config.dig("auto", "command_max_output_bytes") || 20_000).to_i

      result = nil
      Timeout.timeout(timeout_s) do
        result = Util.run_capture(command, chdir: context.repo_path)
      end

      {
        "stdout" => truncate_bytes(result["stdout"].to_s, max_bytes),
        "stderr" => truncate_bytes(result["stderr"].to_s, max_bytes),
        "exit_code" => result["exit_code"].to_i
      }
    rescue Timeout::Error
      {
        "stdout" => "",
        "stderr" => "Command timed out after #{timeout_s}s",
        "exit_code" => 124
      }
    end

    def error_summary(args)
      stderr = args.fetch("stderr").to_s
      context.tracer.event("diagnostics_error_summary", bytes: stderr.bytesize)
      return({ "root_cause" => "", "confidence" => 0.0 }) if stderr.strip.empty?

      raw = context.query(
        role: :developer,
        prompt: <<~PROMPT,
          #{Prompts::DIAGNOSTICS_ERROR_SUMMARY_SYSTEM}

          STDERR:
          #{stderr}
        PROMPT
        stream: false,
        params: { temperature: 0.0 }
      )

      json = JSON.parse(raw.to_s)
      JSON::Validator.validate!(
        {
          "type" => "object",
          "required" => %w[root_cause confidence],
          "properties" => {
            "root_cause" => { "type" => "string" },
            "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
          }
        },
        json
      )
      json
    end

    def git_status(_args)
      context.tracer.event("git_status")
      return({ "stdout" => "", "stderr" => "", "exit_code" => 0 }) if dry_run?
      return({ "stdout" => "", "stderr" => "Not a git repository", "exit_code" => 1 }) unless git_repo?

      r = Util.run_capture("git status --porcelain", chdir: context.repo_path)
      { "stdout" => r["stdout"].to_s, "stderr" => r["stderr"].to_s, "exit_code" => r["exit_code"].to_i }
    end

    def git_diff(args)
      staged = args["staged"] == true
      context.tracer.event("git_diff", staged: staged)
      return({ "stdout" => "", "stderr" => "", "exit_code" => 0 }) if dry_run?
      return({ "stdout" => "", "stderr" => "Not a git repository", "exit_code" => 1 }) unless git_repo?

      cmd = staged ? "git diff --cached" : "git diff"
      r = Util.run_capture(cmd, chdir: context.repo_path)
      { "stdout" => r["stdout"].to_s, "stderr" => r["stderr"].to_s, "exit_code" => r["exit_code"].to_i }
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

    def command_allowed?(command)
      cmd = command.to_s.strip
      return false if cmd.empty?

      deny_patterns = [
        /\Agit\s+push\b/i,
        /\Agit\s+commit\b/i,
        /\Agit\s+reset\b/i,
        /\Agit\s+clean\b/i,
        /\Arm\s+/i,
        /\Asudo\b/i,
        /\bcurl\b.*\|\s*(sh|bash)\b/i,
        /\bwget\b.*\|\s*(sh|bash)\b/i,
        /\bbundle\s+install\b/i,
        /\bnpm\s+install\b/i,
        /\byarn\s+install\b/i
      ]
      return false if deny_patterns.any? { |re| cmd.match?(re) }

      allow = Array(context.config.dig("auto", "command_allowlist"))
      # Empty allowlist means "deny by default" for safety.
      return false if allow.empty?

      allow.any? { |prefix| cmd.start_with?(prefix.to_s) }
    end

    def validate_diff!(path, diff)
      lines = diff.to_s.lines
      raise Error, "diff too large" if lines.count > 200
      raise Error, "diff missing hunk context" unless diff.include?("@@")
      expected = "--- a/#{path}"
      raise Error, "path mismatch in diff" unless diff.to_s.start_with?(expected)
    end

    def truncate_bytes(text, max_bytes)
      return "" if text.nil?
      s = text.to_s
      return s if s.bytesize <= max_bytes

      slice = s.byteslice(0, max_bytes)
      "#{slice}\n... (truncated to #{max_bytes} bytes)"
    end
  end
end
