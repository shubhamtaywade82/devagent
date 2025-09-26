Gaps vs Codex

  - Missing dependency graph: PluginContext needs to expose shell, index, memory, and plugins, populated via a PluginLoader (see
  expectations in code_context.txt and specs). Without this, you don’t get framework‑aware prompts or test runners.
  - Planner must enforce the Codex JSON contract (JSON Schema, confidence field), include repository retrieval, and prepend plugin
  prompt text; otherwise unvalidated plans cause the “relative/path*.txt” failures you’re still seeing.
  - Auto should greet/farewell, display confidence, iterate up to max_iterations, drive test runs via plugin actions, gather feedback
  (git diff, tmp logs), re-plan on failures, and call Executor#finalize_success!. None of that exists yet.
  - Executor should handle the full action set (apply_patch, generate_tests, migrate, etc.), manage git snapshots with rollback on
  failure, honor dry runs, and log diffs. The present stub can’t support Codex workflows.
  - Diagnostics class (see spec/devagent/diagnostics_spec.rb) must run configuration, index, and Ollama connectivity checks, surfacing
  friendly errors when the model isn’t set.
  - CLI needs a test command that runs diagnostics and exits non‑zero on failure.
  - Support utilities (lib/devagent/util.rb, lib/devagent/safety.rb, etc.) should match the richer implementations in code_context.txt,
  including helper methods like text_file?, stricter allow/deny logic, and error messaging.
  - Sample config .devagent.yml should expose Codex defaults (model name, allow/deny lists, index config). The current file is already
  customized but should align with the richer schema once Context changes land.

  Implementation Roadmap

  1. Restore the infrastructure layer: implement Devagent::Plugin, PluginLoader, Index, and Memory modules as outlined in
  code_context.txt, then expand PluginContext to carry those objects (lib/devagent/context.rb).
  2. Rebuild Devagent::Diagnostics per the spec expectations, and wire it into Devagent::CLI by adding the test command that exits with
  Thor::Error (ensuring spec/devagent/cli_spec.rb passes).
  3. Replace Auto with the Codex version: greeting/farewell, plan confidence logging, iteration loop, plugin hooks, test execution,
  feedback gathering, and replanning logic. Handle LLm failures gracefully.
  4. Reintroduce the full executor (snapshot/rollback, dry run, diff logging, apply_patch, generate_tests, migrate, command guardrails)
  and fix existing bugs like the command reference at lib/devagent/executor.rb:63.
  5. Upgrade the planner with JSON schema validation, plugin preface hooks, and repository context retrieval (Index#retrieve), falling
  back to an empty plan on invalid responses.
  6. Restore sample plugins (e.g., lib/devagent/plugins/ruby_gem.rb) so Codex can detect project types, seed prompts, and run the right
  test commands.
  7. Flesh out Util and Safety helper methods to match the richer API, including text/binary detection, allow/deny glob normalization,
  and repository boundary checks.
  8. Once the code matches this feature set, revisit .devagent.yml/.devagent.example.yml, documentation, and CHANGELOG to describe the
  Codex-style workflow.
  9. Re-run and fix RSpec: spec/devagent/auto_spec.rb expects greetings/unrecognized command warnings, and spec/devagent/
  diagnostics_spec.rb requires all three checks to be implemented. Add any missing tests for new modules as you port them.

  Bringing these pieces back will align the gem with the Codex behavior you’re looking for: plugin-aware planning, iterative execution
  with safety rails, diagnostics, and a richer CLI experience.