# 🚀 Design Pattern Enhancements in DevAgent

This document shows **how to use the enhanced design patterns** that have been added to DevAgent.

---

## Table of Contents

1. [PromptBuilder (Builder Pattern)](#promptbuilder-builder-pattern)
2. [EventBus (Enhanced Observer Pattern)](#eventbus-enhanced-observer-pattern)
3. [AgentComposite (Composite Pattern)](#agentcomposite-composite-pattern)
4. [Migration Guide](#migration-guide)

---

## PromptBuilder (Builder Pattern)

### Problem

Building complex prompts was done via string concatenation:

```ruby
def build_prompt(task, feedback)
  retrieved = context.index.retrieve(task, limit: 6).map do |snippet|
    "#{snippet["path"]}:\n#{snippet["text"]}\n---"
  end.join("\n")

  history = context.session_memory.last_turns(8).map do |turn|
    "#{turn["role"]}: #{turn["content"]}"
  end.join("\n")

  prompt = <<~PROMPT
    #{Prompts::PLANNER_SYSTEM}

    Recent conversation:
    #{history}

    Repository context:
    #{retrieved}

    Task:
    #{task}
  PROMPT

  prompt
end
```

**Issues:**
- Hard to add new sections
- Inconsistent formatting
- Difficult to test individual sections
- Easy to mess up the order

### Solution

Use `PromptBuilder` for composable, readable prompts:

```ruby
require "devagent/prompt_builder"

def build_prompt(task, feedback)
  PromptBuilder.new
    .with_system_prompt(:planner)
    .with_memory(context.session_memory)
    .with_context(context.index.retrieve(task, limit: 6))
    .with_tools(context.tool_registry)
    .with_user_input(task)
    .with_feedback(feedback)
    .build
end
```

### Advanced Usage

```ruby
# Custom sections
builder = PromptBuilder.new
  .with_system_prompt(:planner)
  .with_section(:custom, "Add your custom content here")
  .build

# For developer prompts
def build_developer_prompt(context, code_to_implement)
  PromptBuilder.new
    .with_system_prompt(:developer)
    .with_context(context.index.retrieve(code_to_implement))
    .with_section(:instructions, "Implement this feature:")
    .with_user_input(code_to_implement)
    .build
end

# For reviewer prompts
def build_review_prompt(context, plan_json)
  PromptBuilder.new
    .with_system_prompt(:reviewer)
    .with_section(:plan_to_review, plan_json)
    .with_user_input("Review this plan for safety and minimality")
    .build
end
```

### Benefits

✅ **Composable** - Add/remove sections easily
✅ **Clarity** - Self-documenting prompt structure
✅ **Testable** - Can verify each section independently
✅ **Extensible** - New sections don't break existing code

---

## EventBus (Enhanced Observer Pattern)

### Problem

Old `Tracer` only wrote to files:

```ruby
class Tracer
  def event(type, payload = {})
    append(type: type, payload: payload, timestamp: Time.now.utc.iso8601)
  end
end

# Usage
context.tracer.event("plan", summary: "...")
context.tracer.event("execute_action", action: {...})
```

**Issues:**
- Only one output (file)
- No way to subscribe multiple outputs
- Can't add UI updates, Slack notifications, etc.
- Not truly event-driven

### Solution

Use `EventBus` for true pub-sub with multiple subscribers:

```ruby
require "devagent/event_bus"

# Create event bus
event_bus = EventBus.new

# Subscribe file tracer (old behavior)
file_tracer = EventBus::FileTracerAdapter.new(context.repo_path)
event_bus.subscribe_handler(:plan_generated, file_tracer)
event_bus.subscribe_handler(:action_executed, file_tracer)

# Subscribe console logger (UI updates)
console_logger = EventBus::ConsoleLoggerAdapter.new($stdout)
event_bus.subscribe(:plan_generated) { |data| console_logger.call(:plan_generated, data) }
event_bus.subscribe(:action_executed) { |data| console_logger.call(:action_executed, data) }

# Subscribe custom handler (Slack notifications)
event_bus.subscribe(:tests_failed) do |data|
  SlackNotifier.notify("#{data[:summary]} - Tests failed in #{context.repo_path}")
end

# Publish events (replaces tracer.event)
event_bus.publish(:plan_generated, summary: "Add login", confidence: 0.8)
event_bus.publish(:action_executed, type: "fs.write", path: "lib/auth.rb")
event_bus.publish(:tests_failed, summary: "Login tests failed")
```

### Advanced Usage

```ruby
# Multiple subscribers per event
event_bus.subscribe(:plan_generated) { |data| puts "Plan: #{data[:summary]}" }
event_bus.subscribe(:plan_generated) { |data| log_to_database(data) }
event_bus.subscribe(:plan_generated) { |data| send_email_notification(data) }

# Conditional subscriber
event_bus.subscribe(:action_executed) do |data|
  if data[:type] == "fs.write" && data[:path] =~ /spec/
    puts "✓ Test file modified: #{data[:path]}"
  end
end

# Error handling in subscribers (automatic)
event_bus.subscribe(:plan_generated) do |data|
  raise "This won't crash the agent"  # Automatically caught
end

# Check subscribers
puts "Subscribers: #{event_bus.subscribed_types}"  # [:plan_generated, :action_executed, ...]
puts "Count: #{event_bus.subscriber_count(:plan_generated)}"  # 3
```

### Custom Adapters

```ruby
# Create your own adapter
class CustomWebhookAdapter
  def initialize(url)
    @url = url
  end

  def call(event_type, data)
    HTTP.post(@url, json: {
      event: event_type,
      data: data,
      timestamp: Time.now.utc.iso8601
    })
  end
end

# Use it
webhook = CustomWebhookAdapter.new("https://api.example.com/webhook")
event_bus.subscribe_handler(:plan_generated, webhook)
event_bus.subscribe_handler(:action_executed, webhook)
```

### Benefits

✅ **Loose coupling** - Subscribers don't know about each other
✅ **Easy extensibility** - Add new subscribers without changing core
✅ **Multiple outputs** - File, UI, Slack, webhook, etc.
✅ **Testable** - Subscribe test doubles

---

## AgentComposite (Composite Pattern)

### Problem

Orchestrator manually calls each agent:

```ruby
class Orchestrator
  def run(task)
    plan = planner.plan(task)           # Manual call
    execute_actions(plan.actions)        # Manual call
    result = exec_run                    # Manual call
    if result == :failed
      plan = planner.plan(task)         # Manual replan
    end
  end
end
```

**Issues:**
- Tight coupling between Orchestrator and agents
- Hard to add new agents (must modify Orchestrator)
- No way to treat agents as a unit
- Difficult to test agent interactions

### Solution

Use `AgentComposite` to treat multiple agents as a single unit:

```ruby
require "devagent/agent_composite"

# Create agents
planner = PlannerAgent.new(context)
developer = DeveloperAgent.new(context)
tester = TesterAgent.new(context)

# Create composite
agents = AgentComposite.new([planner, developer, tester])

# Run all agents sequentially
result = agents.run(task)

# Result shape:
# {
#   planner: { summary: "...", actions: [...], confidence: 0.8, agent: :planner },
#   developer: { executed: [...], changes_made: true, agent: :developer },
#   tester: { result: :ok, passed: true, agent: :tester }
# }
```

### Advanced Usage

```ruby
# Conditional execution
result = agents.run_conditional(task) do |results|
  if results[:tester][:passed]
    :continue  # All good, continue
  elsif results[:planner][:confidence] > 0.7
    :replan    # High confidence, replan
  else
    :stop      # Low confidence, stop
  end
end

# Adding new agents dynamically
reviewer = ReviewerAgent.new(context)
agents.add(reviewer)

# Removing agents
agents.remove(planner)

# Getting specific agent
planner_agent = agents.get(:planner)

# Checking if agent exists
if agents.contains?(:tester)
  puts "Tests will run"
end
```

### Custom Agents

```ruby
# Create your own agent
class ReviewerAgent < AgentBase
  def process(_task, previous_results = {})
    actions = previous_results[:developer]&.dig(:executed) || []
    issues = []

    actions.each do |action|
      if action["type"] == "fs.write" && !action["path"].include?("spec")
        issues << "No test added for #{action["path"]}"
      end
    end

    {
      issues: issues,
      approved: issues.empty?,
      agent: :reviewer
    }
  end
end

# Use it
agents = AgentComposite.new([
  PlannerAgent.new(context),
  DeveloperAgent.new(context),
  ReviewerAgent.new(context),  # Your custom agent
  TesterAgent.new(context)
])

result = agents.run(task)
```

### Benefits

✅ **Treat multiple agents as one** - Unified interface
✅ **Easy to add/remove** - Dynamic composition
✅ **Consistent interface** - All agents follow same pattern
✅ **Agent chain-of-thought** - Results flow from one to the next

---

## Migration Guide

### From String-based Prompts to PromptBuilder

**Before:**
```ruby
# lib/devagent/planner.rb
def build_prompt(task, feedback)
  retrieved = context.index.retrieve(task, limit: 6).map do |snippet|
    "#{snippet["path"]}:\n#{snippet["text"]}\n---"
  end.join("\n")

  history = context.session_memory.last_turns(8).map do |turn|
    "#{turn["role"]}: #{turn["content"]}"
  end.join("\n")

  <<~PROMPT
    #{Prompts::PLANNER_SYSTEM}

    Recent conversation:
    #{history}

    Repository context:
    #{retrieved}

    Task:
    #{task}
  PROMPT
end
```

**After:**
```ruby
require_relative "prompt_builder"

def build_prompt(task, feedback)
  PromptBuilder.new
    .with_system_prompt(:planner)
    .with_memory(context.session_memory)
    .with_context(context.index.retrieve(task, limit: 6))
    .with_tools(context.tool_registry)
    .with_user_input(task)
    .with_feedback(feedback)
    .build
end
```

### From Tracer to EventBus

**Before:**
```ruby
# lib/devagent/orchestrator.rb
def run(task)
  plan = planner.plan(task)
  context.tracer.event("plan", summary: plan.summary, confidence: plan.confidence)

  execute_actions(plan.actions)

  if failed?
    context.tracer.event("tests_failed")
  end
end
```

**After:**
```ruby
def initialize(context, output: $stdout, ui: nil, event_bus: nil)
  @context = context
  @event_bus = event_bus || EventBus.new
  setup_subscribers!
end

def run(task)
  plan = planner.plan(task)
  @event_bus.publish(:plan_generated, summary: plan.summary, confidence: plan.confidence)

  execute_actions(plan.actions)

  if failed?
    @event_bus.publish(:tests_failed)
  end
end

def setup_subscribers!
  # File logging
  file_tracer = EventBus::FileTracerAdapter.new(context.repo_path)
  @event_bus.subscribe_handler(:plan_generated, file_tracer)
  @event_bus.subscribe_handler(:action_executed, file_tracer)

  # UI updates
  console_logger = EventBus::ConsoleLoggerAdapter.new($stdout)
  @event_bus.subscribe_handler(:plan_generated, console_logger)
  @event_bus.subscribe_handler(:action_executed, console_logger)
end
```

### From Manual Orchestration to AgentComposite

**Before:**
```ruby
# lib/devagent/orchestrator.rb
def run(task)
  plan = planner.plan(task)           # Manual
  execute_actions(plan.actions)        # Manual
  result = exec_run                    # Manual (e.g., exec.run "bundle exec rspec")
  if result == :failed
    replan
  end
end
```

**After:**
```ruby
def run(task)
  agents = AgentComposite.new([
    PlannerAgent.new(context),
    DeveloperAgent.new(context),
    TesterAgent.new(context)
  ])

  result = agents.run_conditional(task) do |results|
    if results[:tester][:passed]
      :continue
    else
      :replan
    end
  end
end
```

---

## Examples

### Example 1: Building a custom agent pipeline

```ruby
require "devagent/agent_composite"

context = Context.build(Dir.pwd)

# Create your pipeline
pipeline = AgentComposite.new([
  PlannerAgent.new(context),
  DeveloperAgent.new(context),
  TestCoverageAgent.new(context),    # Custom agent
  SecurityReviewerAgent.new(context), # Custom agent
  TesterAgent.new(context)
])

# Run with error handling
begin
  result = pipeline.run("Add user authentication")

  if result[:security_reviewer][:approved]
    puts "✅ Security approved"
  else
    puts "❌ Security issues: #{result[:security_reviewer][:issues]}"
  end
rescue => e
  puts "Pipeline failed: #{e.message}"
end
```

### Example 2: Event-driven UI with multiple subscribers

```ruby
require "devagent/event_bus"

event_bus = EventBus.new

# File logging
file_tracer = EventBus::FileTracerAdapter.new(context.repo_path)
event_bus.subscribe_handler(:plan_generated, file_tracer)
event_bus.subscribe_handler(:action_executed, file_tracer)

# Terminal UI
ui = EventBus::ConsoleLoggerAdapter.new($stdout)
event_bus.subscribe_handler(:plan_generated, ui)
event_bus.subscribe_handler(:action_executed, ui)
event_bus.subscribe_handler(:tests_failed, ui)

# Progress bar (custom subscriber)
event_bus.subscribe(:action_executed) do |data|
  ProgressBar.increment
  ProgressBar.status("Modified #{data[:path]}")
end

# Error reporting (custom subscriber)
event_bus.subscribe(:action_failed) do |data|
  ErrorTracker.track(
    action: data[:action],
    error: data[:error],
    context: context.repo_path
  )
end
```

---

## Summary

| Pattern            | Status     | Location                          | Usage                        |
| ------------------ | ---------- | --------------------------------- | ---------------------------- |
| **PromptBuilder**  | ✅ Enhanced | `lib/devagent/prompt_builder.rb`  | Replace string concatenation |
| **EventBus**       | ✅ Enhanced | `lib/devagent/event_bus.rb`       | Replace simple Tracer        |
| **AgentComposite** | ✅ New      | `lib/devagent/agent_composite.rb` | Replace manual orchestration |

**Next Steps:**
1. Migrate `Orchestrator` to use `AgentComposite`
2. Migrate `Planner` to use `PromptBuilder`
3. Add `EventBus` to `Context` for global event handling

---

**See Also:**
- [Design Patterns Overview](./DESIGN_PATTERNS.md)
- [Architecture Guide](./ARCHITECTURE.md)

