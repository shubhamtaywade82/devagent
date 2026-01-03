# frozen_string_literal: true

require_relative "../planning/plan"
require_relative "../context"
require_relative "../diff_generator"
require "shellwords"

module Devagent
  module Execution
    class Executor
      def initialize(repo_path:, context:)
        @repo_path = repo_path
        @context = context
        # Force executor to use qwen2.5-coder:7b
        @executor_model = "qwen2.5-coder:7b"
      end

      def call(plan)
        # Executor ONLY executes given steps - no planning, no reasoning
        results = {}
        plan.steps.each do |step|
          step_id = step["step_id"] || step[:step_id]
          result = execute_step(plan, step)
          results[step_id] = result
        end
        results
      end

      private

      attr_reader :repo_path, :context, :executor_model

      def execute_step(plan, step)
        action = step["action"] || step[:action]
        path = step["path"] || step[:path]
        command = step["command"] || step[:command]
        content = step["content"] || step[:content]

        case action.to_s
        when "fs.read", "fs_read"
          raise Devagent::Error, "path required for fs.read" if path.to_s.empty?

          context.tool_bus.invoke("type" => "fs.read", "args" => { "path" => path })
        when "fs.create"
          raise Devagent::Error, "path required for fs.create" if path.to_s.empty?
          raise Devagent::Error, "file already exists: #{path}" if File.exist?(File.join(repo_path, path.to_s))
          raise Devagent::Error, "content required for fs.create" if content.to_s.empty?

          # Generate diff for new file
          diff = build_add_file_diff(path: path.to_s, content: content.to_s)
          context.tool_bus.invoke("type" => "fs.write_diff", "args" => { "path" => path.to_s, "diff" => diff })
        when "fs.write", "fs_write"
          raise Devagent::Error, "path required for fs.write" if path.to_s.empty?

          # Read original file
          original = context.tool_bus.read_file("path" => path.to_s).fetch("content")
          # Generate diff using diff generator
          diff = DiffGenerator.new(context).generate(
            path: path.to_s,
            original: original,
            goal: plan.goal.to_s,
            reason: (step["reason"] || step[:reason]).to_s,
            file_exists: true
          )
          context.tool_bus.invoke("type" => "fs.write_diff", "args" => { "path" => path.to_s, "diff" => diff })
        when "fs.delete", "fs_delete"
          raise Devagent::Error, "path required for fs.delete" if path.to_s.empty?

          context.tool_bus.invoke("type" => "fs.delete", "args" => { "path" => path.to_s })
        when "exec.run", "run_command", "run_tests"
          raise Devagent::Error, "command required for exec.run" if command.to_s.strip.empty?

          cmd = command.to_s
          cmd = "bundle exec rspec" if action.to_s == "run_tests" && cmd.strip.empty?
          tokens = Shellwords.split(cmd)
          raise Devagent::Error, "command required" if tokens.empty?

          result = context.tool_bus.invoke(
            "type" => "exec.run",
            "args" => {
              "program" => tokens.first,
              "args" => tokens.drop(1),
              "accepted_exit_codes" => step["accepted_exit_codes"] || step[:accepted_exit_codes],
              "allow_failure" => step["allow_failure"] || step[:allow_failure]
            }
          )

          # Check if execution was successful
          exit_code = result.is_a?(Hash) ? result["exit_code"].to_i : 0
          accepted = Array(step["accepted_exit_codes"] || step[:accepted_exit_codes]).map(&:to_i)
          allow_failure = step["allow_failure"] || step[:allow_failure] == true
          success = exit_code == 0 || allow_failure || accepted.include?(exit_code)

          { "success" => success, "artifact" => result }
        when "BOOTSTRAP_REPO"
          # Special action for empty repos - create a basic structure
          # This is a no-op for now, but could create .gitignore, README, etc.
          { "success" => true, "artifact" => { "type" => "BOOTSTRAP_REPO", "message" => "Repository initialized" } }
        else
          raise Devagent::Error, "Unknown step action: #{action}"
        end
      rescue StandardError => e
        { "success" => false, "error" => e.message }
      end

      def build_add_file_diff(path:, content:)
        # Generate unified diff for new file
        <<~DIFF
          --- /dev/null
          +++ b/#{path}
          @@ -0,0 +1,#{content.lines.count} @@
          #{content.lines.map { |line| "+#{line}" }.join}
        DIFF
      end
    end
  end
end
