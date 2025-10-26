# 🧩 Design Patterns in DevAgent

This document maps the design patterns actually implemented in the `devagent` gem to the codebase, showing where each pattern lives and why it matters.

---

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Creational Patterns](#creational-patterns)
3. [Structural Patterns](#structural-patterns)
4. [Behavioral Patterns](#behavioral-patterns)
5. [Pattern Interaction Diagram](#pattern-interaction-diagram)
6. [Future Enhancements](#future-enhancements)

---

## High-Level Architecture

DevAgent follows a **Layered Clean Architecture** combined with an **Event-Driven Agent Loop**.

```
┌─────────────────────────────────────────┐
│ CLI (Facade)                            │
│  ↓ Simple, user-friendly interface      │
├─────────────────────────────────────────┤
│ Orchestrator (Template Method)           │
│  ↓ Defines fixed workflow                │
├─────────────────────────────────────────┤
│ Agents (Composite + Strategy)           │
│  • Planner (Strategy)                    │
│  • Developer (future)                    │
│  • Reviewer (Strategy)                   │
│  • Tester (future)                       │
├─────────────────────────────────────────┤
│ Infrastructure                          │
│  • ToolBus (Command + Chain)            │
│  • Safety (Policy/Guard)                 │
│  • Tracer (Observer)                     │
├─────────────────────────────────────────┤
│ Providers (Adapter + Strategy)          │
│  • LLM (Ollama / OpenAI / Claude)        │
│  • Embeddings (OpenAI / Ollama)         │
│  • Vector Store (SQLite-VSS)            │
└─────────────────────────────────────────┘
```

**Benefits:**
- **Swappable providers** (Ollama ↔ OpenAI)
- **Extensible tools** (fs_write → docker_build)
- **Reusable domain logic** (Planner works for any Ruby project)
- **Testable** (mock LLM, mock ToolBus)

---

## Creational Patterns

### 1️⃣ Factory Method Pattern

**Location:** `lib/devagent/llm.rb:10-16`

```ruby
def for_role(context, role)
  context.llm_cache[role] ||= begin
    provider = context.provider_for(role)
    model = context.model_for(role)
    params = context.llm_params(provider)
    embedding_model = context.embedding_model_for(role, provider)
    build_adapter(context, provider: provider, model: model, params: params, embedding_model: embedding_model)
  end
end
```

**Also:** `lib/devagent/llm.rb:20-40` (build_adapter)

**Why:** Single creation entrypoint avoids conditional code spread everywhere.

**Result:**
```ruby
llm = LLM.for_role(context, :planner)
llm = LLM.for_role(context, :developer)
```

Each role gets the correct adapter automatically.

---

### 2️⃣ Builder Pattern (Partial)

**Location:** `lib/devagent/planner.rb:121-163`

```ruby
def build_prompt(task, feedback)
  retrieved = context.index.retrieve(task, limit: 6).map do |snippet|
    "#{snippet["path"]}:\n#{snippet["text"]}\n---"
  end.join("\n")

  history = context.session_memory.last_turns(8).map do |turn|
    "#{turn["role"]}: #{turn["content"]}"
  end.join("\n")

  plugin_guidance = context.plugins.filter_map do |plugin|
    plugin.on_prompt(context, task) if plugin.respond_to?(:on_prompt)
  end.join("\n")

  # ... assembles into PROMPT
end
```

**Status:** ⚠️ Implicit builder pattern (string concatenation).

**Enhancement Opportunity:** Create a formal `PromptBuilder` class:

```ruby
PromptBuilder.new
  .with_system_prompt(:planner)
  .with_memory(context.session_memory)
  .with_context(retrieved_code)
  .with_user_input(task)
  .with_feedback(feedback)
  .with_tools(context.tool_registry)
  .build
```

---

### 3️⃣ Singleton Pattern (Implicit)

**Location:** `lib/devagent/context.rb` - one instance per repo/session

```ruby
class Context
  attr_reader :repo_path, :config, :memory, :session_memory, :tracer,
              :tool_registry, :tool_bus, :plugins, :index

  def self.build(repo_path, overrides = {})
    config = load_config(repo_path)
    new(repo_path, merged_config, overrides: overrides)
  end
end
```

**Why:** Global access to configuration without messy passing. One context per run.

**Note:** Not a true Singleton (no `include Singleton`), but acts as one per session.

---

## Structural Patterns

### 4️⃣ Adapter Pattern

**Location:** `lib/devagent/llm/ollama_adapter.rb`, `lib/devagent/llm/openai_adapter.rb`

```ruby
module LLM
  class OllamaAdapter
    def query(prompt, params: {}, response_format: nil)
      client.generate(prompt: prompt, model: model, params: merged_params(params))
    end

    def stream(prompt, params: {}, response_format: nil, on_token: nil)
      # stream implementation
    end

    def embed(texts, model: nil)
      # embedding implementation
    end
  end

  class OpenAIAdapter
    # same interface, different implementation
    def query(prompt, params: {}, response_format: nil) ... end
    def stream(prompt, params: {}, response_format: nil, on_token: nil) ... end
    def embed(texts, model: nil) ... end
  end
end
```

**Why:** Normalizes different API structures into consistent internal interfaces.

**Benefit:** Code using `llm.query` doesn't care if it's local (Ollama) or remote (OpenAI).

**Future:** Add `ClaudeAdapter`, `MistralAdapter`.

---

### 5️⃣ Facade Pattern

**Location:** `lib/devagent/cli.rb`

```ruby
class CLI < Thor
  def start(*_args)
    ctx = build_context
    Auto.new(ctx, input: $stdin, output: $stdout).repl
  end
end
```

**Wraps:**
- Context loading
- Provider resolution
- Model selection
- Orchestrator initialization
- UI setup

**Benefit:** User just runs `devagent start` without knowing about Context, LLM, or ToolBus.

---

### 6️⃣ Repository Pattern

**Location:** `lib/devagent/embedding_index.rb`

```ruby
class EmbeddingIndex
  def search(query, k: 8)
    vector = embed_many([query]).first
    return [] unless valid_vector?(vector)

    store.similar(vector, limit: k).map do |entry|
      metadata = entry.metadata
      { "path" => metadata["path"], "chunk_index" => metadata["chunk_index"], "text" => metadata["text"] }
    end
  end
end
```

**Abstraction:** `store.similar()` - could be SQLite, Redis, PostgreSQL, or Pinecone.

**Location:** `lib/devagent/vector_store_sqlite.rb` - concrete implementation

**Benefit:** Clean separation between storage and logic. Can swap backends.

---

### 7️⃣ Decorator Pattern (Partial)

**Location:** `lib/devagent/streamer.rb`

The `Streamer` class decorates plain text with:
- Markdown formatting (`TTY::Markdown`)
- Colorization (`Pastel`)
- Streaming UI updates

**Status:** ⚠️ Decorator pattern is implicit in stream processing, not formalized.

**Enhancement Opportunity:** Create explicit decorator chain:

```ruby
OutputDecorator.new
  .wrap(MarkdownDecorator)
  .wrap(ColorDecorator)
  .wrap(SpinnerDecorator)
```

---

### 8️⃣ Composite Pattern (Future)

**Current:** Not formally implemented, but multi-agent structure exists.

**Opportunity:** Formalize agent composition:

```ruby
class AgentComposite
  def initialize(agents)
    @agents = agents
  end

  def run(task)
    @agents.each { |agent| agent.process(task) }
  end
end

composite = AgentComposite.new([
  PlannerAgent.new,
  DeveloperAgent.new,
  TesterAgent.new,
  ReviewerAgent.new
])
```

**Current Reality:** `Orchestrator` manually calls `planner.plan()`, `tool_bus.invoke()`, etc.

---

## Behavioral Patterns

### 9️⃣ Command Pattern

**Location:** `lib/devagent/tool_registry.rb`, `lib/devagent/tool_bus.rb`

**ToolRegistry** defines commands:

```ruby
ToolRegistry.default.tools = [
  Tool.new(name: "fs_write", handler: :write_file, schema: {...}),
  Tool.new(name: "git_apply", handler: :apply_patch, schema: {...}),
  Tool.new(name: "run_tests", handler: :run_tests, schema: {...}),
  Tool.new(name: "run_command", handler: :run_command, schema: {...})
]
```

**ToolBus** executes commands:

```ruby
def invoke(action)
  name = action.fetch("type")
  args = action.fetch("args", {})
  tool = registry.validate!(name, args)
  send(tool.handler, args)  # execute command
rescue StandardError => e
  context.tracer.event("tool_error", tool: name, message: e.message)
  raise
end
```

**Benefit:**
- Commands are **loggable** (Tracer records them)
- Commands are **replayable** (could save/load sessions)
- Commands are **undoable** (future: `git_revert` on failure)
- New commands don't require Orchestrator changes

---

### 🔟 Strategy Pattern

**Location:** LLM adapters, embedding strategies, provider selection

**Example 1: LLM Provider Strategy**

```ruby
def build_adapter(context, provider:, model:, params:, embedding_model: nil)
  case provider
  when "openai"
    LLM::OpenAIAdapter.new(...)
  else
    LLM::OllamaAdapter.new(...)
  end
end
```

**Example 2: Embedding Strategy**

```ruby
def embedding_model_for(role, provider)
  return model_for(:embedding) if role == :embedding
  provider == "openai" ? config["embed_model"] : nil
end
```

**Why:** Allows switching strategies dynamically without changing core logic.

**Use cases:**
- Switch from Ollama to OpenAI for better quality
- Use cheaper models for planning, expensive for code review
- Embed with different models per role

---

### 1️⃣1️⃣ Observer Pattern (Partial)

**Location:** `lib/devagent/tracer.rb`

```ruby
class Tracer
  def event(type, payload = {})
    append(type: type, payload: payload, timestamp: Time.now.utc.iso8601)
  end
end
```

**Published Events:**
- `plan` - New plan generated
- `execute_action` - Tool executed
- `write_file` - File modified
- `tests_failed` - Tests failed
- `plan_review_rejected` - Plan review failed

**Status:** ⚠️ Basic pub-sub (only writes to file). Not fully event-driven.

**Enhancement:** Create formal observer chain:

```ruby
module Observer
  def subscribe(event_type, &callback)
    @subscribers ||= {}
    @subscribers[event_type] ||= []
    @subscribers[event_type] << callback
  end

  def publish(event_type, data)
    @subscribers[event_type]&.each { |cb| cb.call(data) }
  end
end
```

Then multiple subscribers:
- `FileTracer` → writes traces.jsonl
- `UI::Logger` → prints to terminal
- `SessionMemory` → saves to session
- `WebhookNotifier` → sends to Slack

---

### 1️⃣2️⃣ Template Method Pattern

**Location:** `lib/devagent/orchestrator.rb:20-39`

```ruby
def run(task)
  context.session_memory.append("user", task)
  with_spinner("Indexing") { context.index.build! }
  return answer_unactionable(task, 1.0) if qna?(task)

  plan = with_spinner("Planning") { planner.plan(task) }
  context.tracer.event("plan", ...)
  return answer_unactionable(task, plan.confidence) if plan.actions.empty?

  iterations.times do |iteration|
    streamer.say("Iteration #{iteration + 1}/#{iterations}")
    context.tool_bus.reset!
    execute_actions(plan.actions)
    break unless retry_needed?(iteration, task, plan.confidence)

    plan = with_spinner("Planning") { planner.plan(task) }
  end
end
```

**Fixed steps:**
1. Build index
2. Generate plan
3. Execute actions (loop)
4. Run tests (conditional)
5. Replan if failed (conditional)
6. Finalize

**Why:** Core flow is predictable and extensible.

**Extension points:**
- Plugins can override `on_prompt`, `on_action`, `on_post_edit`
- Subclasses can override `execute_actions`, `run_tests`

---

### 1️⃣3️⃣ Chain of Responsibility

**Location:** `lib/devagent/plugin.rb`

```ruby
module Plugin
  def on_prompt(_ctx, _task)
    ""  # Pass along by default
  end

  def on_action(_ctx, _name, _args = {})
    nil  # Pass along by default
  end
end
```

**Usage in Rails Plugin:** `lib/devagent/plugins/rails.rb`

```ruby
module Rails
  def self.on_prompt(_ctx, _task)
    if rails_file?(_task)
      "You're working on a Rails app. Include migrations, models, controllers..."
    else
      super
    end
  end

  def self.test_command(ctx)
    "bundle exec rspec" if rails_project?(ctx.repo_path)
  end
end
```

**Chain:** Each plugin decides to handle or pass along the request.

**Benefit:** Extensible system where new frameworks can hook in without core changes.

---

### 1️⃣4️⃣ State Pattern (Future)

**Current:** Not explicitly implemented as a state machine.

**Opportunity:** Formalize agent states:

```ruby
class AgentState
  TRANSITIONS = {
    :idle => [:planning],
    :planning => [:executing, :idle],
    :executing => [:testing, :planning],
    :testing => [:reviewing, :planning],
    :reviewing => [:done, :planning]
  }

  def transition(new_state)
    raise "Invalid transition" unless TRANSITIONS[@state].include?(new_state)
    @state = new_state
  end
end
```

**Status:** Implicit state management in `Orchestrator.run`:

```ruby
:idle → :planning → :executing → :testing → :reviewing → :done
```

---

### 1️⃣5️⃣ Policy/Guard Pattern

**Location:** `lib/devagent/safety.rb`

```ruby
class Safety
  def allowed?(relative_path)
    return false if SYSTEM_DENY_REL.any? { |regex| relative_path.match?(regex) }
    return false unless inside_repo?(relative_path)

    absolute = absolute_path(relative_path)
    return false if SYSTEM_DENY_ABS.any? { |regex| absolute.match?(regex) }

    allowed = glob_match?(@allow, relative_path)
    denied = glob_match?(@deny, relative_path)
    allowed && !denied
  end
end
```

**Enforces:**
- Path must be relative (no `/`, `~`, `..`)
- Must be inside repo
- Must match allowlist globs
- Must not match denylist globs

**Used by:** `ToolBus` before executing any file write:

```ruby
def guard_path!(relative_path)
  raise Error, "path required" if relative_path.to_s.empty?
  raise Error, "path not allowed: #{relative_path}" unless safety.allowed?(relative_path)
end
```

**Benefit:** Centralized control over all destructive operations.

---

### 1️⃣6️⃣ Memento Pattern

**Location:** `lib/devagent/session_memory.rb`

```ruby
class SessionMemory
  def append(role, content)
    write_line(role: role, content: content, timestamp: Time.now.utc.iso8601)
    truncate!
  end

  def last_turns(count = limit)
    read_lines.last(count)
  end
end
```

**Stored as JSONL:**

```json
{"role":"user","content":"add login api","timestamp":"2025-01-15T10:30:00Z"}
{"role":"assistant","content":"Added files...","timestamp":"2025-01-15T10:30:05Z"}
```

**Benefit:**
- Store conversation history
- Restore previous state
- Summarize long sessions
- Debug agent behavior

---

### 1️⃣7️⃣ Service Object Pattern

**Location:** Throughout the codebase

Each subsystem acts as a **service object** — stateless classes with `.call` or `.run`.

**Examples:**

```ruby
# PlannerService (implicit)
class Planner
  def plan(task)
    generate_plan(task, feedback)
  end
end

# ToolBusService
class ToolBus
  def invoke(action)
    name = action.fetch("type")
    send(tool.handler, args)
  end
end

# QueryService (implicit)
context.query(role: :developer, prompt: "...")
```

**Also see:** `Memory`, `Tracer`, `Safety`, `EmbeddingIndex`

**Benefit:**
- **Testable** - Easy to mock
- **Composable** - Use together
- **Predictable** - Clear inputs/outputs
- **Rails-style** - Familiar to Rubyists

---

### 1️⃣8️⃣ Value Object Pattern (Partial)

**Location:** `lib/devagent/planner.rb:8`

```ruby
Plan = Struct.new(:summary, :actions, :confidence, keyword_init: true)
```

**Status:** ⚠️ Basic struct, not fully immutable.

**Enhancement:** Create proper value objects:

```ruby
class Plan
  def initialize(summary:, actions:, confidence:)
    @summary = summary.to_s.freeze
    @actions = actions.freeze
    @confidence = confidence.to_f
    raise "Confidence out of range" unless @confidence.between?(0, 1)
  end

  attr_reader :summary, :actions, :confidence

  def approved?
    confidence >= 0.7 && !actions.empty?
  end
end
```

**Also:** `Entry` in `EmbeddingIndex` (line 22) is a Struct, but not immutable.

---

## Pattern Interaction Diagram

```
[CLI (Facade)]
      ↓
 [Context (Singleton-ish)]
      ↓
 [Orchestrator (Template Method)]
      ↓
 [Planner (Strategy + Service Object)]
      ↓
 [ToolBus (Command + Chain of Responsibility)]
      ↓
 [ToolRegistry (Command Registry)]
      ↓
 [fs_write, git_apply, run_tests (Commands)]
      ↓
 [Safety (Policy/Guard)]
      ↓
 [Tracer (Observer - writes events)]
      ↓
 [SessionMemory (Memento - stores state)]
```

**Also:**

```
[Context]
      ↓
 [LLM Factory Method]
      ↓
 [Strategy Selection]
      ↓
 [OllamaAdapter | OpenAIAdapter (Adapter)]
      ↓
 [Ollama/OpenAI API]
```

---

## Future Enhancements

### Enhancements to Existing Patterns

| Pattern      | Current                          | Enhanced                                  | Effort |
| ------------ | -------------------------------- | ----------------------------------------- | ------ |
| Builder      | Implicit string concatenation    | Formal `PromptBuilder` class              | Low    |
| Decorator    | Streamer has implicit decorators | Explicit decorator chain                  | Medium |
| Observer     | File-only event writing          | Multiple subscribers (UI, webhook, Slack) | Medium |
| State        | Implicit in Orchestrator         | Formal state machine class                | Low    |
| Composite    | Manual agent coordination        | AgentComposite orchestrator               | Medium |
| Value Object | Basic Structs                    | Immutable classes with validation         | Low    |

### New Patterns to Add

| Pattern           | Use Case                                            | Implementation             |
| ----------------- | --------------------------------------------------- | -------------------------- |
| **Specification** | Complex query logic (`Query.filter_by(allowed?)`)   | `PathSpec`, `FileTypeSpec` |
| **Pipeline**      | Chaining filters (`plan → post_process → validate`) | `ActionPipeline`           |
| **Mediator**      | Coordinate between Planner, Developer, Tester       | `AgentMediator`            |
| **Proxy**         | Lazy loading for large embeddings                   | `LazyEmbeddingProxy`       |
| **Flyweight**     | Share common tool descriptions                      | `ToolDescriptorFlyweight`  |

---

## Summary Table

| Category       | Pattern                 | Location                           | Status        | Notes                            |
| -------------- | ----------------------- | ---------------------------------- | ------------- | -------------------------------- |
| **Creational** | Factory Method          | `llm.rb`                           | ✅ Implemented | LLM adapter creation             |
|                | Builder                 | `planner.rb`                       | ⚠️ Implicit    | String building, could be formal |
|                | Singleton               | `context.rb`                       | ✅ Implemented | Implicit via build()             |
| **Structural** | Adapter                 | `llm/*_adapter.rb`                 | ✅ Implemented | LLM providers                    |
|                | Facade                  | `cli.rb`                           | ✅ Implemented | CLI interface                    |
|                | Repository              | `embedding_index.rb`               | ✅ Implemented | Vector storage                   |
|                | Decorator               | `streamer.rb`                      | ⚠️ Implicit    | Output formatting                |
|                | Composite               | N/A                                | ❌ Missing     | Multi-agent orchestration        |
| **Behavioral** | Command                 | `tool_registry.rb` + `tool_bus.rb` | ✅ Implemented | Tool execution                   |
|                | Strategy                | LLM, embeddings, providers         | ✅ Implemented | Multiple strategies              |
|                | Observer                | `tracer.rb`                        | ⚠️ Partial     | File-only, needs subscribers     |
|                | Template Method         | `orchestrator.rb`                  | ✅ Implemented | Fixed workflow                   |
|                | Chain of Responsibility | `plugin.rb`                        | ✅ Implemented | Plugin system                    |
|                | State                   | N/A                                | ❌ Missing     | Agent lifecycle                  |
|                | Memento                 | `session_memory.rb`                | ✅ Implemented | Conversation history             |
|                | Policy/Guard            | `safety.rb`                        | ✅ Implemented | Path restrictions                |
|                | Service Object          | Throughout                         | ✅ Implemented | Multiple services                |

---

## Conclusion

DevAgent already implements **14 major design patterns** with varying levels of formality. The architecture is solid, extensible, and testable.

**Strengths:**
- ✅ Clear separation of concerns
- ✅ Swappable providers (LLM, embeddings, storage)
- ✅ Extensible via plugins
- ✅ Safe execution via Safety layer
- ✅ Observable via Tracer

**Next Steps:**
1. Formalize implicit patterns (Builder, Decorator, State)
2. Add missing patterns (Composite, formal Observer chain)
3. Enhance value objects (immutability, validation)
4. Document each pattern with examples

---

**See Also:**
- [Architecture Overview](./ARCHITECTURE.md)
- [Plugin Development Guide](./PLUGINS.md)
- [Testing Guide](./TESTING.md)

