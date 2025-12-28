# frozen_string_literal: true

require "json-schema"

module Devagent
  # ToolRegistry describes available tool actions and validation rules.
  class ToolRegistry
    Tool = Struct.new(
      :name,
      :schema,
      :handler,
      :description,
      :allowed_phases,
      :visible_phases,
      :depends_on,
      :side_effects,
      :safety,
      keyword_init: true
    )

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

    def tools_for_phase(phase)
      phase_sym = phase.to_sym
      tools.select do |_name, tool|
        vis = tool.visible_phases
        vis.nil? || Array(vis).map(&:to_sym).include?(phase_sym)
      end
    end

    def self.default
      new([
        Tool.new(
          name: "fs_read",
          schema: {
            "type" => "object",
            "required" => ["path"],
            "properties" => {
              "path" => { "type" => "string" }
            }
          },
          handler: :read_file,
          description: "Read a text file from inside the repo.",
          allowed_phases: %i[execution],
          visible_phases: %i[planning],
          depends_on: [],
          side_effects: ["READS_FS"],
          safety: ["NO_READ_OUTSIDE_PROJECT"]
        ),
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
          description: "Write or replace the full contents of a file.",
          allowed_phases: %i[execution],
          visible_phases: %i[planning],
          depends_on: ["fs_read"],
          side_effects: ["MODIFIES_FS"],
          safety: ["NO_WRITE_OUTSIDE_PROJECT"]
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
          description: "Apply a unified diff patch with git apply.",
          allowed_phases: %i[execution],
          visible_phases: %i[planning],
          depends_on: [],
          side_effects: ["MODIFIES_FS"],
          safety: ["NO_WRITE_OUTSIDE_PROJECT"]
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
          description: "Run the preferred test command (RSpec/Jest).",
          allowed_phases: %i[execution],
          visible_phases: %i[planning],
          depends_on: [],
          side_effects: ["EXECUTES_COMMAND"],
          safety: ["WHITELISTED_ONLY"]
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
          description: "Run a whitelisted shell command inside the repo.",
          allowed_phases: %i[execution],
          visible_phases: [],
          depends_on: [],
          side_effects: ["EXECUTES_COMMAND"],
          safety: ["WHITELISTED_ONLY"]
        )
      ])
    end
  end
end
