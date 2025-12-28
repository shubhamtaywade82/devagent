# DevAgent Documentation

Comprehensive documentation for the `devagent` gem, covering architecture, design patterns, and usage.

---

## 📚 Documentation Index

### Core Documentation

1. **[Design Patterns](./DESIGN_PATTERNS.md)**
   - Complete mapping of all 18+ design patterns used in DevAgent
   - Shows where each pattern lives in the codebase
   - Explains why each pattern was chosen
   - Includes architectural diagrams

2. **[Pattern Enhancements](./PATTERN_ENHANCEMENTS.md)**
   - Guide to using enhanced patterns
   - Examples: `PromptBuilder`, `EventBus`, `AgentComposite`
   - Migration guide from old to new patterns
   - Real-world usage examples

### Pattern Examples

#### PromptBuilder (Builder Pattern)
```ruby
PromptBuilder.new
  .with_system_prompt(:planner)
  .with_memory(context.session_memory)
  .with_context(retrieved_code)
  .with_tools(context.tool_registry)
  .with_user_input(task)
  .build
```

#### EventBus (Enhanced Observer Pattern)
```ruby
event_bus.subscribe(:plan_generated) { |data| puts data[:summary] }
event_bus.publish(:plan_generated, summary: "...", confidence: 0.8)
```

#### AgentComposite (Composite Pattern)
```ruby
agents = AgentComposite.new([planner, developer, tester])
result = agents.run(task)
```

---

## 🎯 Quick Start

### Understanding the Architecture

DevAgent uses **Layered Clean Architecture** with an **Event-Driven Agent Loop**:

```
CLI (Facade)
  ↓
Orchestrator (Template Method)
  ↓
Agents (Composite + Strategy)
  ↓
Infrastructure (Command + Chain + Observer)
  ↓
Providers (Adapter + Strategy)
```

### Key Design Patterns

| Pattern             | Location                          | Purpose             |
| ------------------- | --------------------------------- | ------------------- |
| **Factory Method**  | `lib/devagent/llm.rb`             | Create LLM adapters |
| **Strategy**        | `lib/devagent/llm/*_adapter.rb`   | Ollama vs OpenAI    |
| **Command**         | `lib/devagent/tool_registry.rb`   | Tool execution      |
| **Observer**        | `lib/devagent/tracer.rb`          | Event logging       |
| **Template Method** | `lib/devagent/orchestrator.rb`    | Fixed workflow      |
| **Policy/Guard**    | `lib/devagent/safety.rb`          | Path restrictions   |
| **Facade**          | `lib/devagent/cli.rb`             | Simple interface    |
| **Repository**      | `lib/devagent/embedding_index.rb` | Vector storage      |

---

## 🧩 Pattern Implementations

### Implemented Patterns (14)

✅ **Factory Method** - `LLM.build_adapter`
✅ **Strategy** - LLM providers, embeddings
✅ **Command** - `ToolRegistry` + `ToolBus`
✅ **Adapter** - `OllamaAdapter`, `OpenAIAdapter`
✅ **Facade** - `CLI`
✅ **Repository** - `EmbeddingIndex`
✅ **Observer** - `Tracer` (basic)
✅ **Template Method** - `Orchestrator.run`
✅ **Chain of Responsibility** - `Plugin` system
✅ **Policy/Guard** - `Safety`
✅ **Memento** - `SessionMemory`
✅ **Singleton** - `Context` (implicit)
✅ **Service Object** - Throughout
✅ **Builder** - `PromptBuilder` (enhanced)

### Enhanced Patterns (3)

🔄 **Builder** → Formal `PromptBuilder` class
🔄 **Observer** → `EventBus` with multiple subscribers
🔄 **Composite** → `AgentComposite` for multi-agent orchestration

---

## 📖 Reading Guide

### For Developers

1. Start with [Design Patterns](./DESIGN_PATTERNS.md) to understand the architecture
2. Read [Pattern Enhancements](./PATTERN_ENHANCEMENTS.md) for usage examples
3. Implement your own plugins or agents using the pattern guide

### For Architects

1. Review the [Architecture Diagram](#understanding-the-architecture)
2. Study the [Pattern Interaction Diagram](./DESIGN_PATTERNS.md#pattern-interaction-diagram)
3. Explore enhancement opportunities in [Future Enhancements](./DESIGN_PATTERNS.md#future-enhancements)

### For Contributors

1. Understand existing patterns before making changes
2. Follow the pattern conventions when adding new features
3. Reference the [Migration Guide](./PATTERN_ENHANCEMENTS.md#migration-guide) when refactoring

---

## 🔍 Finding Patterns in the Codebase

### Pattern Search Tips

```bash
# Find all Factory Methods
grep -r "def self.build" lib/

# Find all Strategy patterns
ls lib/devagent/llm/*_adapter.rb

# Find all Commands
grep -r "Tool.new" lib/

# Find all Observers
grep -r ".event(" lib/
```

### Key Files

| File                              | Pattern(s)                   |
| --------------------------------- | ---------------------------- |
| `lib/devagent/llm.rb`             | Factory Method, Strategy     |
| `lib/devagent/orchestrator.rb`    | Template Method              |
| `lib/devagent/tool_registry.rb`   | Command Pattern              |
| `lib/devagent/tracer.rb`          | Observer Pattern (basic)     |
| `lib/devagent/safety.rb`          | Policy/Guard Pattern         |
| `lib/devagent/context.rb`         | Singleton Pattern            |
| `lib/devagent/plugin.rb`          | Chain of Responsibility      |
| `lib/devagent/prompt_builder.rb`  | Builder Pattern (enhanced)   |
| `lib/devagent/event_bus.rb`       | Observer Pattern (enhanced)  |
| `lib/devagent/agent_composite.rb` | Composite Pattern (enhanced) |

---

## 🚀 Next Steps

### Enhancements

1. **Formalize State Pattern**
   - Create `AgentStateMachine` class
   - Track transitions explicitly
   - Add validation

2. **Add Mediator Pattern**
   - Create `AgentMediator` to coordinate agents
   - Decouple Orchestrator from direct agent calls

3. **Add Specification Pattern**
   - Create `PathSpec`, `FileTypeSpec` classes
   - Enhance Safety with composable specs

4. **Add Pipeline Pattern**
   - Create `ActionPipeline` for chaining filters
   - Plan → post_process → validate → execute

### Contributing

Want to contribute? Start by:
1. Reading the existing patterns documentation
2. Finding areas that need enhancement
3. Following the pattern conventions
4. Adding tests for new pattern implementations

---

## 📚 Resources

- [Design Patterns: Elements of Reusable Object-Oriented Software](https://en.wikipedia.org/wiki/Design_Patterns)
- [Ruby Design Patterns](https://github.com/nslocum/design-patterns-in-ruby)
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)

---

## Summary

DevAgent is **not just a Ruby script** — it's a carefully designed AI agent framework using 14+ design patterns that make it:

✅ **Extensible** → Add new providers easily
✅ **Safe** → Centralized Safety layer
✅ **Clear** → Each subsystem follows SRP
✅ **Testable** → Service Objects and Adapters
✅ **Maintainable** → Open architecture like Cursor/Copilot

By understanding **which patterns power DevAgent and why**, you can extend it confidently and maintain it long-term.

