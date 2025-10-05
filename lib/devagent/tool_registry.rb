# frozen_string_literal: true

require "json-schema"

module Devagent
  # ToolRegistry describes available tool actions and validation rules.
  class ToolRegistry
    Tool = Struct.new(:name, :schema, :handler, :description, keyword_init: true)

    attr_reader :tools

    def initialize(tools)
      @tools = tools.each_with_object({}) { |tool, memo| memo[tool.name] = tool }
    end

    def fetch(name)
      tools[name]
    end

    def validate!(name, args)
      tool = fetch(name)
      raise Error, "Unknown tool #{name}" unless tool

      JSON::Validator.validate!(tool.schema, args || {}) if tool.schema
      tool
    end

    def self.default
      new([
        Tool.new(
          name: "fs_write",
          schema: {
            "type" => "object",
            "required" => %w[path content],
            "properties" => {
              "path" => { "type" => "string" },
              "content" => { "type" => "string" }
            }
          },
          handler: :write_file,
          description: "Write or replace the full contents of a file."
        ),
        Tool.new(
          name: "git_apply",
          schema: {
            "type" => "object",
            "required" => %w[patch],
            "properties" => {
              "patch" => { "type" => "string" }
            }
          },
          handler: :apply_patch,
          description: "Apply a unified diff patch with git apply."
        ),
        Tool.new(
          name: "run_tests",
          schema: {
            "type" => "object",
            "properties" => {
              "command" => { "type" => "string" }
            }
          },
          handler: :run_tests,
          description: "Run the preferred test command (RSpec/Jest)."
        ),
        Tool.new(
          name: "run_command",
          schema: {
            "type" => "object",
            "required" => ["command"],
            "properties" => {
              "command" => { "type" => "string" }
            }
          },
          handler: :run_command,
          description: "Run a whitelisted shell command inside the repo."
        )
      ])
    end
  end
end
