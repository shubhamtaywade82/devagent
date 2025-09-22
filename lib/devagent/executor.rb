# frozen_string_literal: true

require "diffy"
require "fileutils"
require_relative "safety"
require_relative "util"

module Devagent
  # Executor applies planned actions, runs commands, and manages rollback/snapshots.
  # rubocop:disable Metrics/ClassLength
  class Executor
    attr_reader :log

    ACTION_HANDLERS = {
      "create_file" => :handle_create_file,
      "edit_file" => :handle_edit_file,
      "apply_patch" => :handle_apply_patch,
      "run_command" => :handle_run_command,
      "generate_tests" => :handle_generate_tests,
      "migrate" => :handle_migrate
    }.freeze

    def initialize(ctx)
      @ctx = ctx
      @repo = ctx.repo_path
      @safety = Safety.new(ctx)
      @dry_run = ctx.config.dig("auto", "dry_run") ? true : false
      @log = []
      @snapshot_ref = nil
    end

    def snapshot!
      return if @dry_run

      run_and_log_system("git", "-C", @repo, "add", "-A")
      run_and_log_system("git", "-C", @repo, "commit", "-m", "devagent: pre-change snapshot", "--allow-empty")
      @snapshot_ref = `git -C #{@repo} rev-parse HEAD`.strip
    end

    def rollback!
      return if @dry_run || @snapshot_ref.nil?

      run_and_log_system("git", "-C", @repo, "reset", "--hard", @snapshot_ref)
    end

    def finalize_success!(message = "devagent: implement request")
      return if @dry_run

      run_and_log_system("git", "-C", @repo, "add", "-A")
      run_and_log_system("git", "-C", @repo, "commit", "-m", message)
    end

    def apply(plan)
      actions = Array(plan.respond_to?(:actions) ? plan.actions : plan)
      snapshot!
      actions.each { |action| apply_action(action) }
    rescue StandardError => e
      @log << "ERROR: #{e.message}"
      rollback!
      raise
    end

    def run_tests!(command = "bundle exec rspec")
      run_command(command)
    end

    def apply_action(action)
      type = action.fetch("type")
      handler = ACTION_HANDLERS[type]
      return @log << "Unknown action: #{action.inspect}" unless handler

      public_send(handler, action)
    end

    def create_file(relative_path, content)
      guard_path!(relative_path)
      @log << "create_file #{relative_path}"
      return if @dry_run

      absolute = File.join(@repo, relative_path)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, content)
    end

    def edit_file(relative_path, content, _whole_file)
      guard_path!(relative_path)
      raise "content required for edit" if content.nil?

      absolute = File.join(@repo, relative_path)
      original = File.exist?(absolute) ? File.read(absolute) : ""
      rendered_diff = Diffy::Diff.new(original, content, context: 3).to_s(:text)
      @log << "edit_file #{relative_path}"
      @log << rendered_diff unless rendered_diff.empty?
      return if @dry_run

      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, content)
    end

    def apply_patch(patch)
      raise "patch required" if patch.to_s.strip.empty?

      @log << "apply_patch"
      return if @dry_run

      IO.popen(["git", "-C", @repo, "apply", "--reject", "--whitespace=fix", "-"], "w") do |io|
        io.write(patch)
      end
      raise "git apply failed" unless $CHILD_STATUS&.success?
    end

    def run_command(command)
      raise "command required" if command.to_s.strip.empty?

      @log << "run: #{command}"
      return command if @dry_run

      Util.run!(command, chdir: @repo)
    end

    def generate_tests(path)
      if should_generate_spec?(path)
        create_spec_from_source(path)
      else
        initialize_rspec_suite
      end
    end

    def guess_spec_path(source)
      return File.join("spec", "generated_spec.rb") unless source&.end_with?(".rb")

      relative = source.sub(%r{^app/}, "")
      File.join("spec", relative.sub(/\.rb$/, "_spec.rb"))
    end

    private

    def handle_create_file(action)
      create_file(action["path"], action["content"] || "")
    end

    def handle_edit_file(action)
      edit_file(action["path"], action["content"], action["whole_file"])
    end

    def handle_apply_patch(action)
      apply_patch(action["patch"])
    end

    def handle_run_command(action)
      run_command(action["command"])
    end

    def handle_generate_tests(action)
      generate_tests(action["path"])
    end

    def handle_migrate(_action)
      run_command("bundle exec rails db:migrate")
    end

    def should_generate_spec?(path)
      path && !path.empty? && File.exist?(File.join(@repo, path))
    end

    def create_spec_from_source(path)
      source_path = File.join(@repo, path)
      content = File.read(source_path)
      spec_prompt = "Write comprehensive RSpec for this file:\n\n#{content}"
      spec = @ctx.llm.call(spec_prompt)
      spec_path = guess_spec_path(path)
      @log << "generate_tests -> #{spec_path}"
      return if @dry_run

      absolute_spec = File.join(@repo, spec_path)
      FileUtils.mkdir_p(File.dirname(absolute_spec))
      File.write(absolute_spec, spec)
    end

    def initialize_rspec_suite
      @log << "generate_tests -> rspec --init"
      run_command("bundle exec rspec --init")
    end

    def guard_path!(relative_path)
      raise "path required" if relative_path.to_s.empty?
      raise "path not allowed: #{relative_path}" unless @safety.allowed?(relative_path)
    end

    def run_and_log_system(*cmd)
      system(*cmd)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
