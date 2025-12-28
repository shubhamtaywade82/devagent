# frozen_string_literal: true

require "json-schema"

module Devagent
  # ToolRegistry describes available tool actions and validation rules.
  #
  # This registry distinguishes between:
  # - LLM-visible logical tools (declarative contracts)
  # - Controller-only execution tools (internal, imperative)
  #
  # The planner is only shown visible tools for the current phase, as structured JSON.
  class ToolRegistry
    Tool = Struct.new(
      :name,
      :category,
      :description,
      :purpose,
      :when_to_use,
      :when_not_to_use,
      :inputs_schema,
      :outputs_schema,
      :allowed_phases,
      :forbidden_phases,
      :dependencies,
      :side_effects,
      :safety_rules,
      :examples,
      :handler,
      :internal,
      :visible_phases,
      keyword_init: true
    ) do
      def visible?
        internal != true
      end

      def allowed_in_phase?(phase)
        p = phase.to_sym
        return false if Array(forbidden_phases).map(&:to_sym).include?(p)
        return true if allowed_phases.nil? || Array(allowed_phases).empty?

        Array(allowed_phases).map(&:to_sym).include?(p)
      end

      # Contract JSON injected into the planner prompt.
      def to_contract_hash
        {
          "name" => name,
          "category" => category,
          "description" => description,
          "purpose" => purpose,
          "when_to_use" => Array(when_to_use),
          "when_not_to_use" => Array(when_not_to_use),
          "dependencies" => dependencies || {},
          "inputs" => inputs_schema,
          "outputs" => outputs_schema,
          "side_effects" => Array(side_effects),
          "safety_rules" => Array(safety_rules),
          "examples" => examples || {}
        }
      end
    end

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

      JSON::Validator.validate!(tool.inputs_schema, args || {}) if tool.inputs_schema
      tool
    end

    def visible_tools_for_phase(phase)
      phase_sym = phase.to_sym
      tools.values.select do |tool|
        next false unless tool.visible?

        vis = tool.visible_phases
        vis.nil? || Array(vis).map(&:to_sym).include?(phase_sym)
      end
    end

    def tools_for_phase(phase)
      phase_sym = phase.to_sym
      tools.select do |_name, tool|
        next false unless tool.visible?

        vis = tool.visible_phases
        vis.nil? || Array(vis).map(&:to_sym).include?(phase_sym)
      end
    end

    def self.default
      new([
        Tool.new(
          name: "fs.read",
          category: "filesystem",
          description: "Read the contents of a file from disk.",
          purpose: "Inspect existing code before making changes.",
          when_to_use: [
            "Before modifying a file",
            "When debugging code behavior",
            "When validating assumptions about implementation"
          ],
          when_not_to_use: [
            "If file content is already available in context",
            "To explore the repository blindly",
            "To read more than one file in the first iteration"
          ],
          inputs_schema: {
            "type" => "object",
            "required" => ["path"],
            "properties" => {
              "path" => { "type" => "string", "description" => "Relative path to file inside repo" }
            }
          },
          outputs_schema: {
            "type" => "object",
            "required" => %w[path content],
            "properties" => {
              "path" => { "type" => "string" },
              "content" => { "type" => "string" }
            }
          },
          allowed_phases: %i[planning execution],
          forbidden_phases: %i[decision],
          dependencies: {
            "allowed_phases" => %w[PLANNING EXECUTION],
            "forbidden_phases" => ["DECISION"],
            "produces" => ["file_content"],
            "required_before" => []
          },
          side_effects: ["Reads from disk", "Does not modify filesystem"],
          safety_rules: [
            "Must not be called more than once in the first planning iteration",
            "Must not be used to scan directories"
          ],
          examples: {
            "valid" => [
              {
                "input" => { "path" => "lib/devagent/tool_registry.rb" },
                "output" => { "path" => "lib/devagent/tool_registry.rb", "content" => "..." }
              }
            ],
            "invalid" => [
              { "input" => {}, "reason" => "Missing required path" }
            ]
          },
          handler: :read_file,
          internal: false,
          visible_phases: %i[planning]
        ),
        Tool.new(
          name: "fs.write",
          category: "filesystem",
          description: "Propose modifications to an existing file (logical only).",
          purpose: "Safely change code after inspection. The controller converts this intent into a diff and applies it.",
          when_to_use: [
            "After reading a file to propose a small, targeted change",
            "When implementing a fix described in the plan"
          ],
          when_not_to_use: [
            "Before reading the same file",
            "To rewrite an entire file",
            "To make large, sweeping refactors in one step"
          ],
          inputs_schema: {
            "type" => "object",
            "required" => %w[path intent],
            "properties" => {
              "path" => { "type" => "string" },
              "intent" => { "type" => "string", "description" => "What change is being made and why" }
            }
          },
          outputs_schema: {
            "type" => "object",
            "properties" => {
              "proposed_change" => { "type" => "string", "description" => "Unified diff generated by controller" }
            }
          },
          allowed_phases: %i[planning execution],
          forbidden_phases: %i[decision],
          dependencies: {
            "required_tools" => ["fs.read"],
            "required_outputs" => ["file_content"],
            "requires_same_path" => true
          },
          side_effects: ["None (controller converts to diff)"],
          safety_rules: [
            "Must depend on fs.read of the same path",
            "Must not rewrite entire file",
            "Controller must validate diff before applying"
          ],
          examples: {
            "valid" => [
              {
                "input" => { "path" => "lib/devagent/tool_registry.rb", "intent" => "Expose only logical tools to the planner" },
                "output" => { "proposed_change" => "--- a/lib/devagent/tool_registry.rb\n+++ b/lib/devagent/tool_registry.rb\n@@ ..." }
              }
            ],
            "invalid" => [
              { "input" => { "path" => "lib/devagent/tool_registry.rb" }, "reason" => "Missing required intent" }
            ]
          },
          handler: nil, # logical-only: controller translates to internal fs.write_diff
          internal: false,
          visible_phases: %i[planning]
        ),
        Tool.new(
          name: "exec.run",
          category: "execution",
          description: "Run a safe shell command and capture output.",
          purpose: "Run tests, linters, or simple diagnostics.",
          when_to_use: [
            "To run test suites",
            "To validate a fix",
            "To reproduce a reported error"
          ],
          when_not_to_use: [
            "To install dependencies",
            "To push code",
            "To modify system state"
          ],
          inputs_schema: {
            "type" => "object",
            "required" => ["command"],
            "properties" => {
              "command" => { "type" => "string", "description" => "Shell command (allowlisted)" }
            }
          },
          outputs_schema: {
            "type" => "object",
            "required" => %w[stdout stderr exit_code],
            "properties" => {
              "stdout" => { "type" => "string" },
              "stderr" => { "type" => "string" },
              "exit_code" => { "type" => "integer" }
            }
          },
          allowed_phases: %i[planning execution],
          forbidden_phases: %i[decision],
          dependencies: {
            "allowed_phases" => ["EXECUTION"],
            "produces" => ["command_output"]
          },
          side_effects: ["Consumes CPU", "May read files", "Does not modify files"],
          safety_rules: [
            "Command must match allowlist",
            "Block rm, sudo, git push, curl | sh",
            "Hard timeout enforced",
            "Max output size enforced"
          ],
          examples: {
            "valid" => [
              {
                "input" => { "command" => "bundle exec rspec" },
                "output" => { "stdout" => "...", "stderr" => "", "exit_code" => 0 }
              }
            ],
            "invalid" => [
              { "input" => { "command" => "rm -rf /" }, "reason" => "Blocked by denylist" }
            ]
          },
          handler: :run_command,
          internal: false,
          visible_phases: %i[planning]
        ),
        Tool.new(
          name: "diagnostics.error_summary",
          category: "diagnostics",
          description: "Summarize an error output.",
          purpose: "Extract likely root cause from logs without executing anything.",
          when_to_use: [
            "After a failing exec.run step to extract the root cause",
            "When stderr is long and needs reduction"
          ],
          when_not_to_use: [
            "When there is no stderr",
            "To replace actually reading relevant code"
          ],
          inputs_schema: {
            "type" => "object",
            "required" => ["stderr"],
            "properties" => {
              "stderr" => { "type" => "string" }
            }
          },
          outputs_schema: {
            "type" => "object",
            "required" => %w[root_cause confidence],
            "properties" => {
              "root_cause" => { "type" => "string" },
              "confidence" => { "type" => "number" }
            }
          },
          allowed_phases: %i[planning execution],
          forbidden_phases: %i[decision],
          dependencies: {
            "produces" => ["error_summary"]
          },
          side_effects: ["None"],
          safety_rules: ["Must not fabricate output; use only provided stderr"],
          examples: {
            "valid" => [
              {
                "input" => { "stderr" => "NameError: uninitialized constant Foo" },
                "output" => { "root_cause" => "Foo constant is missing or not required/loaded", "confidence" => 0.7 }
              }
            ],
            "invalid" => [
              { "input" => {}, "reason" => "Missing required stderr" }
            ]
          },
          handler: :error_summary,
          internal: false,
          visible_phases: %i[planning]
        ),
        Tool.new(
          name: "fs.write_diff",
          category: "filesystem",
          description: "Apply a unified diff to a file (controller-only).",
          purpose: "Execution primitive for diff-first edits. The LLM must not call this directly.",
          inputs_schema: {
            "type" => "object",
            "required" => %w[path diff],
            "properties" => {
              "path" => { "type" => "string" },
              "diff" => { "type" => "string" }
            }
          },
          outputs_schema: {
            "type" => "object",
            "properties" => {
              "applied" => { "type" => "boolean" }
            }
          },
          allowed_phases: %i[execution],
          forbidden_phases: %i[planning decision],
          dependencies: {
            "internal" => true,
            "validates" => %w[diff_size diff_headers file_mtime]
          },
          side_effects: ["Modifies filesystem"],
          safety_rules: [
            "Validate unified diff headers",
            "Reject oversized diffs",
            "Reject path mismatches"
          ],
          examples: {},
          handler: :write_diff,
          internal: true,
          visible_phases: []
        ),
        Tool.new(
          name: "fs.delete",
          category: "filesystem",
          description: "Delete a file inside the repo (requires prior read).",
          purpose: "Remove files safely after inspection.",
          inputs_schema: {
            "type" => "object",
            "required" => ["path"],
            "properties" => {
              "path" => { "type" => "string" }
            }
          },
          outputs_schema: {
            "type" => "object",
            "properties" => { "ok" => { "type" => "boolean" } }
          },
          allowed_phases: %i[planning execution],
          forbidden_phases: %i[decision],
          dependencies: {
            "required_tools" => ["fs.read"],
            "requires_same_path" => true
          },
          side_effects: ["Modifies filesystem"],
          safety_rules: ["Must depend on fs.read of same path"],
          examples: {},
          handler: :delete_file,
          internal: false,
          visible_phases: %i[planning]
        ),
        Tool.new(
          name: "git.status",
          category: "git",
          description: "Show git working tree status (read-only).",
          purpose: "Inspect repository state (modified/untracked files) without changing anything.",
          when_to_use: ["When you need to see what changed before/after an edit"],
          when_not_to_use: ["To stage/commit/push (not supported via tools)"],
          inputs_schema: {
            "type" => "object",
            "properties" => {}
          },
          outputs_schema: {
            "type" => "object",
            "required" => %w[stdout stderr exit_code],
            "properties" => {
              "stdout" => { "type" => "string" },
              "stderr" => { "type" => "string" },
              "exit_code" => { "type" => "integer" }
            }
          },
          allowed_phases: %i[planning execution],
          forbidden_phases: %i[decision],
          dependencies: {
            "produces" => ["git_status"],
            "optional" => true
          },
          side_effects: ["Reads .git metadata"],
          safety_rules: ["Read-only; must not modify repository state"],
          examples: {
            "valid" => [{ "input" => {}, "output" => { "stdout" => "...", "stderr" => "", "exit_code" => 0 } }],
            "invalid" => []
          },
          handler: :git_status,
          internal: false,
          visible_phases: %i[planning]
        ),
        Tool.new(
          name: "git.diff",
          category: "git",
          description: "Show git diff (read-only).",
          purpose: "Inspect code changes produced by the controller.",
          when_to_use: ["After edits to review the patch"],
          when_not_to_use: ["To apply patches (controller-only)"],
          inputs_schema: {
            "type" => "object",
            "properties" => {
              "staged" => { "type" => "boolean" }
            }
          },
          outputs_schema: {
            "type" => "object",
            "required" => %w[stdout stderr exit_code],
            "properties" => {
              "stdout" => { "type" => "string" },
              "stderr" => { "type" => "string" },
              "exit_code" => { "type" => "integer" }
            }
          },
          allowed_phases: %i[planning execution],
          forbidden_phases: %i[decision],
          dependencies: {
            "produces" => ["git_diff"],
            "optional" => true
          },
          side_effects: ["Reads .git metadata"],
          safety_rules: ["Read-only; must not modify repository state"],
          examples: {
            "valid" => [{ "input" => { "staged" => false }, "output" => { "stdout" => "...", "stderr" => "", "exit_code" => 0 } }],
            "invalid" => []
          },
          handler: :git_diff,
          internal: false,
          visible_phases: %i[planning]
        )
      ])
    end
  end
end
