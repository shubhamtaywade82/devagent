# DevAgent Usage Guide

A complete guide to using DevAgent for controller-driven, bounded coding tasks.

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
```

### 3. Start Using It

Once started, you'll see:
```
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

### Configuration files (global vs project)

Devagent uses two different configuration files with different scopes:

- **Global user config** (`~/.devagent.yml`)
  - Provider defaults
  - **Ollama host** (`ollama.host`) and timeouts (`ollama.timeout`)
  - Preferences that should apply regardless of which directory you run `devagent` from

- **Project config** (`.devagent.yml` in the repo root)
  - File allowlist/denylist (sandbox)
  - Project-specific model choices
  - Test commands / indexing rules

Project config never overrides Ollama host; host resolution is always global (CLI/ENV/`~/.devagent.yml`/default).

### Your project `.devagent.yml` file

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
  params:
    temperature: 0.2

openai:
  uri_base: "http://localhost:11434"
  api_key: "ollama"
```

### Ollama host resolution (recommended)

Devagent resolves the Ollama host without depending on the current working directory:

1. **CLI flag**: `--ollama-host http://...`
2. **Environment variable**: `OLLAMA_HOST=http://...`
3. **User config**: `~/.devagent.yml` (`ollama.host`)
4. **Default**: `http://localhost:11434`

Examples:

```bash
export OLLAMA_HOST=http://192.168.1.14:11434
devagent --provider ollama

devagent --provider ollama --ollama-host http://localhost:11434
```

User config (`~/.devagent.yml`):

```yaml
ollama:
  host: http://192.168.1.14:11434
  timeout: 60
```

Inspect resolved config:

```bash
devagent config
devagent diag
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
- Runs tests (when applicable)
- Makes decisions:
  - **SUCCESS** - Task complete
  - **RETRY** - Try again with changes
  - **HALT** - Stop (blocked or repeated failures)

Iteration is strictly bounded by a controller-enforced maximum and halts on repeated failures or low confidence.

---

## Example Workflow

```
devagent> add a factorial function to lib/math.rb

[⠇] Classifying ...
[⠇] Indexing ...
[⠇] Planning ...
Plan: Add factorial function (85%)

[1/2] fs.read lib/math.rb
[2/2] fs.write lib/math.rb
[⠇] Running tests ...
✓ Tests passed

SUCCESS: Task completed
```

---

## Available Tools

DevAgent can use these tools:

- **fs.read** - Read files
- **fs.write** - Propose edits (controller applies diff)
- **fs.create** - Create new files (controller applies diff)
- **fs.delete** - Delete files
- **exec.run** - Execute allowlisted shell commands
- **diagnostics.error_summary** - Summarize stderr into likely root cause

All file modifications are applied via controller-generated diffs. The language model never writes files directly.

`exec.run` uses a structured command form (program + args), not a raw shell string.

### Code Quality Tools

DevAgent automatically integrates with code quality tools:

**Rubocop (Ruby):**
- Automatically runs `rubocop` to check for style violations
- Uses `rubocop -a` to auto-fix violations
- Verifies fixes with a final `rubocop` check
- Ensures generated code follows Ruby best practices

**Other Linters:**
- Similar auto-fix support can be added for other languages
- Configure in your `.devagent.yml` if needed

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

### 4. Workspace Awareness

**When developing devagent gem itself:**
- New files are automatically created in `playground/` directory
- This keeps test files and examples separate from the gem codebase
- Example: `exe/devagent "Create a calculator class"` → creates `playground/calculator.rb`

**When using devagent in your project:**
- New files go to standard project directories (`lib/`, `src/`, `app/`, etc.)
- DevAgent detects the project structure automatically

### 5. Code Quality

DevAgent automatically:
- Follows language-specific best practices (Ruby, JavaScript, Python, etc.)
- Runs linters (rubocop for Ruby) and auto-fixes violations
- Ensures generated code passes style checks
- Adds proper documentation and comments

**For Ruby:**
- Always includes `# frozen_string_literal: true`
- Adds YARD documentation
- Follows Ruby style guide
- Passes rubocop checks

### 6. File Operations

- **Creating files**: DevAgent uses `fs.create` with complete content
- **Modifying files**: If a file already exists, DevAgent automatically converts "create" to "modify"
- **Dependencies**: DevAgent ensures files are read before being written

### 7. Check Results
DevAgent will, when applicable:
- Show planned and executed steps
- Run allowlisted test commands
- Run linters and fix violations
- Verify success via observed results
- Ask for clarification if blocked

---

## Troubleshooting

### "No chunks indexed"
- Check your embedding provider/model settings and connectivity.
- Run: `devagent diag` and `devagent test`

### "Connection refused"
- Check if Ollama server is running
- Verify host via `devagent config` (and/or `OLLAMA_HOST`, `~/.devagent.yml`, `--ollama-host`)
- Test: `curl http://localhost:11434/api/tags`

### "Plan rejected"
- Confidence too low
- Invalid tool usage
- Missing dependencies
- **Solution**: Be more specific in your request

### "Halting: repeated decision"
- Agent is stuck in a loop
- **Solution**: Provide more context or break down the task

### "Wrong model behavior" / "poor results"
- Check: `devagent diag` (provider + selected models)
- Model size matters (e.g., 3B vs 8B vs 70B): smaller models often struggle with multi-step edits and strict schemas
- Context/window settings (e.g., `openai.options.num_ctx`) can limit planning quality

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
- Create new files with complete, production-ready code
- Add functions/classes following best practices
- Implement features with proper error handling
- Automatically fix code style violations

✅ **Code Modification**
- Refactor code while maintaining functionality
- Fix bugs and errors
- Add features to existing code
- Improve code quality and readability

✅ **Code Quality**
- Automatically run linters (rubocop for Ruby)
- Auto-fix style violations
- Follow language-specific best practices
- Ensure code passes style checks

✅ **Testing**
- Write comprehensive tests
- Run test suites
- Verify changes work correctly

✅ **Documentation**
- Explain code and how it works
- Answer questions about the codebase
- Provide context and examples
- Generate API documentation

✅ **Workspace Management**
- Automatically detect workspace context
- Use appropriate directories for new files
- Handle file creation vs modification intelligently

---

## Limitations

⚠️ **Environment dependencies**
- Devagent will not install system dependencies for you (Ruby, Bundler, Node, etc.). Ensure your environment is set up first.

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

