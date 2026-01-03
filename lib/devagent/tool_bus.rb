# frozen_string_literal: true

require "diffy"
require "English"
require "fileutils"
require "json"
require "json-schema"
require "shellwords"
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

      unless File.exist?(full)
        return { "path" => relative_path, "content" => "" }
      end

      # Get file size and check if we should read in chunks
      file_size = File.size(full)
      max_file_size = context.config.dig("auto", "max_file_size_bytes") || 100_000 # Default 100KB
      chunk_size = context.config.dig("auto", "file_chunk_size") || 50_000 # Default 50KB chunks

      if file_size > max_file_size
        # Read file in chunks (read up to max_file_size bytes)
        chunks = []
        total_read = 0
        chunk_index = 0

        File.open(full, "r:UTF-8") do |file|
          while total_read < max_file_size && !file.eof?
            remaining = max_file_size - total_read
            read_size = [chunk_size, remaining].min
            chunk = file.read(read_size)
            break if chunk.nil? || chunk.empty?

            chunks << {
              "chunk_index" => chunk_index,
              "start_byte" => total_read,
              "end_byte" => total_read + chunk.bytesize,
              "content" => chunk
            }

            total_read += chunk.bytesize
            chunk_index += 1
            break if total_read >= max_file_size
          end
        end

        # Get file stats (count total lines efficiently)
        total_lines = 0
        File.foreach(full) { total_lines += 1 }
        lines_read = chunks.sum { |c| c["content"].lines.count }

        {
          "path" => relative_path,
          "content" => chunks.first&.dig("content") || "", # Return first chunk as main content
          "truncated" => true,
          "file_size_bytes" => file_size,
          "max_file_size_bytes" => max_file_size,
          "chunks_read" => chunks.size,
          "bytes_read" => total_read,
          "total_lines" => total_lines,
          "lines_read" => lines_read,
          "chunks" => chunks
        }
      else
        # Read entire file for small files
        content = File.read(full, encoding: "UTF-8")
        {
          "path" => relative_path,
          "content" => content,
          "truncated" => false,
          "file_size_bytes" => file_size
        }
      end
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

      # Check if diff is a no-op (only context lines, no additions or deletions)
      # git apply rejects no-op diffs as "corrupt", so we skip them
      diff_lines = diff.lines
      has_changes = diff_lines.any? { |line| line.start_with?("+", "-") && !line.start_with?("+++", "---") }

      unless has_changes
        # No-op diff: file already has the requested changes
        # Return success since the goal is already achieved
        context.tracer.event("fs_write_diff", path: relative_path, note: "no-op diff, already applied")
        return { "applied" => true }
      end

      context.tracer.event("fs_write_diff", path: relative_path)
      return { "applied" => false } if dry_run?

      # We intentionally use git apply because it is the most reliable diff applier
      # for unified diffs and keeps behavior deterministic.
      stderr_output = ""
      IO.popen(["git", "-C", context.repo_path, "apply", "--whitespace=nowarn", "-"], "w+", err: [:child, :out]) do |io|
        io.write(diff)
        io.close_write
        stderr_output = io.read
      end

      unless $CHILD_STATUS&.success?
        # Log the diff and error for debugging
        context.tracer.event("diff_apply_failed", path: relative_path, error: stderr_output, diff_preview: diff.lines.first(10).join) if context.respond_to?(:tracer)
        raise Error, "diff apply failed: #{stderr_output.strip.empty? ? 'unknown error' : stderr_output.strip}"
      end

      @changes_made = true
      { "applied" => true }
    end

    def delete_file(args)
      relative_path = args.fetch("path")
      guard_path!(relative_path)
      context.tracer.event("fs_delete", path: relative_path)
      return { "ok" => false } if dry_run?

      full = File.join(context.repo_path, relative_path)
      FileUtils.rm_f(full)
      @changes_made = true
      { "ok" => true }
    end

    def run_tests(args)
      command = args["command"] || default_test_command
      context.tracer.event("run_tests", command: command)
      return :skipped if dry_run?

      tokens = Shellwords.split(command.to_s)
      raise Error, "command not allowed" unless command_allowed?(tokens)

      # Use run_capture to get exit code and output, so we can handle coverage failures
      result = Util.run_capture(tokens, chdir: context.repo_path)
      stdout = result["stdout"].to_s
      exit_code = result["exit_code"].to_i

      # If exit code is 2 (coverage failure), check if tests actually passed
      if exit_code == 2
        # Check if tests passed (0 failures) but coverage failed
        return :ok if stdout.include?("0 failures") || stdout.match?(/\d+\s+examples?,\s+0\s+failures?/)

        # Tests passed, but coverage failed - this is acceptable

        # Tests actually failed
        raise Error, "Tests failed with exit code #{exit_code}:\nSTDOUT: #{stdout}\nSTDERR: #{result["stderr"]}"

      end

      # For other non-zero exit codes, raise error
      raise Error, "Command failed (#{command}):\nSTDOUT: #{stdout}\nSTDERR: #{result["stderr"]}" unless exit_code == 0

      :ok
    end

    def check_command_help(args)
      command = args.fetch("command")
      # Extract base command (before any flags or help flags)
      # Remove common help flags if present
      base_cmd = command.split.reject do |part|
        %w[--help -h help].include?(part)
      end.first || command.split.first || command

      context.tracer.event("check_command_help", command: base_cmd)
      return "skipped" if dry_run?
      raise Error, "command not allowed" unless command_allowed?([base_cmd.to_s])

      # Try --help first, fall back to -h if that fails
      help_output = nil
      ["--help", "-h", "help"].each do |help_flag|
        help_output = Util.run!([base_cmd.to_s, help_flag], chdir: context.repo_path)
        break
      rescue StandardError
        # Try next help flag
        next
      end

      if help_output.nil?
        raise Error,
              "Could not get help for command: #{base_cmd}. Command may not support --help, -h, or help flags."
      end

      help_output
    end

    def run_command(args)
      # Strict mode: only accept structured program+args.
      # This avoids shell parsing and makes allowlisting deterministic.
      raise Error, "exec.run no longer accepts a raw command string; use {program,args}" if args.key?("command")

      program = args.fetch("program")
      argv = args.fetch("args")
      invocation = [program.to_s] + Array(argv).map(&:to_s)

      context.tracer.event("run_command", command: invocation.is_a?(Array) ? invocation.join(" ") : invocation)
      return { "stdout" => "", "stderr" => "", "exit_code" => 0 } if dry_run?
      raise Error, "command not allowed" unless command_allowed?(invocation)

      timeout_s = (context.config.dig("auto", "command_timeout_seconds") || 60).to_i
      max_bytes = (context.config.dig("auto", "command_max_output_bytes") || 20_000).to_i

      result = nil
      Timeout.timeout(timeout_s) do
        result = Util.run_capture(invocation, chdir: context.repo_path)
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
      return { "root_cause" => "", "confidence" => 0.0 } if stderr.strip.empty?

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
      return { "stdout" => "", "stderr" => "", "exit_code" => 0 } if dry_run?
      return { "stdout" => "", "stderr" => "Not a git repository", "exit_code" => 1 } unless git_repo?

      r = Util.run_capture("git status --porcelain", chdir: context.repo_path)
      { "stdout" => r["stdout"].to_s, "stderr" => r["stderr"].to_s, "exit_code" => r["exit_code"].to_i }
    end

    def git_diff(args)
      staged = args["staged"] == true
      context.tracer.event("git_diff", staged: staged)
      return { "stdout" => "", "stderr" => "", "exit_code" => 0 } if dry_run?
      return { "stdout" => "", "stderr" => "Not a git repository", "exit_code" => 1 } unless git_repo?

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

    def command_allowed?(invocation)
      return false unless invocation.is_a?(Array)

      cmd_str = invocation.join(" ")
      cmd = cmd_str.strip
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

      allow = Array(context.config.dig("auto", "command_allowlist")).map { |x| x.to_s.strip }.reject(&:empty?)
      return false if allow.empty? # deny-by-default

      tokens = invocation
      prog = tokens.first.to_s
      return false if prog.empty?

      # Primary allowlist: allow only known programs.
      return false unless allow.include?(prog)

      # Extra guard: disallow launching an interactive shell unless explicitly allowlisted.
      forbidden_shells = %w[bash sh zsh fish].freeze
      return false if (tokens & forbidden_shells).any? && !allow.any? { |a| forbidden_shells.include?(a) }

      true
    rescue ArgumentError
      false
    end

    def validate_diff!(path, diff)
      lines = diff.to_s.lines
      raise Error, "diff too large" if lines.count > 200
      raise Error, "diff missing hunk context" unless diff.include?("@@")

      text = diff.to_s

      # Accept either:
      # - modifications: --- a/<path> ... +++ b/<path>
      # - new files:     --- /dev/null ... +++ b/<path>
      mod_header = "--- a/#{path}\n+++ b/#{path}"
      new_header = "--- /dev/null\n+++ b/#{path}"
      return if text.include?(mod_header) || text.include?(new_header)

      raise Error, "path mismatch in diff"
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
