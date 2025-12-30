# frozen_string_literal: true

require_relative "diff_generator"

module Devagent
  class Bootstrapper
    def initialize(context)
      @context = context
    end

    # Execute a deterministic bootstrap plan (fs.create steps only).
    def run!(plan)
      steps = Array(plan.fetch("steps"))
      raise Error, "bootstrap plan has no steps" if steps.empty?

      steps.each do |step|
        action = step.fetch("action").to_s
        raise Error, "bootstrap only supports fs.create (got #{action})" unless action == "fs.create"

        path = step.fetch("path").to_s
        content = step.fetch("content").to_s
        raise Error, "path required" if path.empty?
        raise Error, "content required" if content.empty?

        full = File.join(context.repo_path, path)
        raise Error, "file already exists: #{path}" if File.exist?(full)

        diff = DiffGenerator.build_add_file_diff(path: path, content: content)
        context.tool_bus.invoke("type" => "fs.write_diff", "args" => { "path" => path, "diff" => diff })
      end

      true
    end

    private

    attr_reader :context
  end
end

