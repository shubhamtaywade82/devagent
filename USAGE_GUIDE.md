# DevAgent Usage Guide

A complete guide to using DevAgent for autonomous coding tasks.

---

## Quick Start

### 1. Start DevAgent

```bash
# Basic usage (auto-detects provider)
./exe/devagent

# Or use the installed gem
devagent
```

### 2. Choose Your Provider

```bash
# Use OpenAI (if API key is set)
devagent --provider openai

# Use Ollama (local)
devagent --provider ollama

# Or use provider-specific commands (if available)
devagent openai
devagent ollama
```

### 3. Start Using It

Once started, you'll see:
```
🔌 Devagent Provider Configuration
  Provider: ollama
  Host: http://localhost:11434
  Models:
    planner: llama3.2:3b
    developer: llama3.2:3b
    reviewer: llama3.1:8b
  Embeddings: ollama (nomic-embed-text)

ℹ info    Devagent ready. Type 'exit' to quit.
devagent>
```

---

## Basic Commands

### Ask Questions
```
devagent> what is this repo about?
devagent> explain how the planner works
devagent> what files are in the lib directory?
```

### Request Code Changes
```
devagent> add a hello world function
devagent> create a User model with email and name
devagent> add error handling to the API endpoint
devagent> refactor the authentication code
```

### Complex Tasks
```
devagent> implement user authentication with JWT
devagent> add a REST API for products
devagent> write tests for the User model
devagent> fix the bug in the payment processor
```

---

## Configuration

### Your `.devagent.yml` File

Located in your project root, this file controls:
- Provider (Ollama/OpenAI)
- Models for each role
- File access permissions
- Test commands

**Example:**
```yaml
provider: auto
model: "llama3.2:3b"
planner_model: "llama3.2:3b"
developer_model: "llama3.2:3b"
reviewer_model: "llama3.1:8b"
embed_model: "nomic-embed-text"

ollama:
  host: "http://localhost:11434"

openai:
  uri_base: "http://localhost:11434"
  api_key: "ollama"
```

---

## How It Works

### 1. Intent Classification
DevAgent first classifies your request:
- **ACTION** - Needs code changes
- **EXPLANATION** - Just answering questions
- **GENERAL** - General conversation
- **REJECT** - Can't handle

### 2. Planning Phase
For action requests, it creates a plan:
- Breaks down into steps
- Validates tool usage
- Checks dependencies
- Estimates confidence

### 3. Execution Phase
Executes the plan step by step:
- Reads files (if needed)
- Writes code (with diffs)
- Runs commands
- Runs tests

### 4. Observation & Decision
After execution:
- Observes results
- Runs tests
- Makes decisions:
  - **SUCCESS** - Task complete
  - **RETRY** - Try again with changes
  - **HALT** - Stop (blocked or repeated failures)

---

## Example Workflow

```
devagent> add a factorial function to lib/math.rb

[⠇] Classifying ...
[⠇] Indexing ...
[⠇] Planning ...
Plan: Add factorial function (85%)

[1/2] fs_read lib/math.rb
[2/2] fs_write lib/math.rb
[⠇] Running tests ...
✓ Tests passed

SUCCESS: Task completed
```

---

## Available Tools

DevAgent can use these tools:

- **fs_read** - Read files
- **fs_write** - Write files (with diff generation)
- **fs_delete** - Delete files
- **run_tests** - Run test suite
- **run_command** - Execute shell commands

---

## Safety Features

### File Access Control
Configured in `.devagent.yml`:
```yaml
auto:
  allowlist:
    - "app/**"
    - "lib/**"
    - "spec/**"
  denylist:
    - ".git/**"
    - "node_modules/**"
    - ".env*"
```

### Validation
- Plans validated before execution
- File reads required before writes
- Dependency checking
- Tool phase restrictions

---

## Tips & Best Practices

### 1. Be Specific
```
❌ Bad: "fix the bug"
✅ Good: "fix the null pointer exception in UserController#show"
```

### 2. Break Down Complex Tasks
```
❌ Bad: "build a complete e-commerce system"
✅ Good: "add a Product model with name, price, and description"
```

### 3. Use Clear Intentions
```
✅ "add authentication"
✅ "refactor the payment module"
✅ "write tests for User model"
```

### 4. Check Results
DevAgent will:
- Show what it's doing
- Run tests automatically
- Report success/failure
- Ask for clarification if needed

---

## Troubleshooting

### "No chunks indexed"
- **With Ollama**: Expected - embeddings disabled for stability
- **With OpenAI**: Check if embeddings are working
- **Solution**: Use `devagent openai` for full features

### "Connection refused"
- Check if Ollama server is running
- Verify host in `.devagent.yml`
- Test: `curl http://localhost:11434/api/tags`

### "Plan rejected"
- Confidence too low
- Invalid tool usage
- Missing dependencies
- **Solution**: Be more specific in your request

### "Halting: repeated decision"
- Agent is stuck in a loop
- **Solution**: Provide more context or break down the task

---

## Advanced Usage

### Override Models
```bash
devagent --model llama3.1:8b --planner-model llama3.1:8b
```

### Diagnostics
```bash
devagent diag
```

### Test Connection
```bash
devagent test
```

### Dry Run Mode
In `.devagent.yml`:
```yaml
auto:
  dry_run: true  # Shows what would be done without making changes
```

---

## Exit Commands

In the REPL:
- `exit` - Exit DevAgent
- `quit` - Exit DevAgent
- `Ctrl+C` - Interrupt current operation

---

## What DevAgent Can Do

✅ **Code Generation**
- Create new files
- Add functions/classes
- Implement features

✅ **Code Modification**
- Refactor code
- Fix bugs
- Add features to existing code

✅ **Testing**
- Write tests
- Run test suites
- Verify changes

✅ **Documentation**
- Explain code
- Answer questions
- Provide context

---

## Limitations

⚠️ **No Code Context with Native Ollama**
- Use `devagent openai` for better results

⚠️ **File Access Restrictions**
- Only files in allowlist
- Protected paths blocked

⚠️ **Model Limitations**
- Smaller models = simpler tasks
- Complex tasks need better models

---

## Getting Help

```bash
# Show all commands
devagent help

# Show specific command help
devagent help start
devagent help diag
```

---

## Next Steps

1. **Start Simple**: Try basic questions first
2. **Test Small Changes**: Add a simple function
3. **Build Up**: Gradually try more complex tasks
4. **Review Changes**: Always review what DevAgent does
5. **Use Git**: Commit before letting DevAgent make changes

---

**Happy coding with DevAgent! 🚀**

