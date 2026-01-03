# DevAgent Features

This document describes the key features and capabilities of DevAgent.

---

## Core Features

### 1. Intent Classification

DevAgent automatically classifies your requests into different intent types:

- **CODE_EDIT**: Create, modify, update, refactor, or enhance code/files
- **CODE_REVIEW**: Review, critique, or audit code
- **DEBUG**: Fix errors, exceptions, or bugs
- **EXPLANATION**: Answer questions about code (what, how, why)
- **GENERAL**: General conversational requests
- **REJECT**: Requests that should be rejected for safety/security

### 2. Intelligent Planning

DevAgent creates step-by-step plans for code changes:

- Breaks down complex tasks into manageable steps
- Validates tool usage before execution
- Checks dependencies between steps
- Estimates confidence for each plan
- Automatically handles file creation vs modification

### 3. Workspace Detection

DevAgent automatically detects the workspace context:

- **When running inside devagent gem**: Uses `playground/` directory for new files
- **When running in external projects**: Uses standard project directories (`lib/`, `src/`, `app/`, etc.)

This ensures that when developing the devagent gem itself, test files and examples go to `playground/`, not `lib/`.

### 4. Code Quality Integration

#### Rubocop Auto-Fix

DevAgent automatically fixes code style violations:

1. **Checks for issues**: Runs `rubocop` to detect style violations
2. **Auto-fixes**: Runs `rubocop -a` to automatically correct violations
3. **Verifies**: Runs `rubocop` again to confirm all issues are fixed

This ensures generated code follows Ruby best practices and passes style checks.

#### Language-Specific Best Practices

DevAgent follows language-specific best practices when generating code:

**Ruby:**
- Always includes `# frozen_string_literal: true` at the top
- Adds top-level documentation comments for classes and modules
- Omits parentheses in method definitions when no arguments
- Follows Ruby style guide and idiomatic patterns
- Ensures code passes rubocop style checks

**Other Languages:**
- JavaScript/TypeScript: Follows ESLint/TypeScript best practices
- Python: Follows PEP 8 style guide
- Java: Follows Java coding conventions
- Go: Follows Go conventions and idioms
- Rust: Follows Rust conventions and idioms
- PHP: Follows PSR standards

### 5. File Operation Handling

#### Smart File Creation/Modification

DevAgent intelligently handles file operations:

- **New files**: Uses `fs.create` with complete content
- **Existing files**: Automatically converts `fs.create` to `fs.read` + `fs.write` if file exists
- **Dependencies**: Ensures proper step dependencies (read before write)

#### Path Normalization

- Handles relative paths (`./file.rb`, `../file.rb`)
- Normalizes paths for validation and execution
- Respects allowlist/denylist configurations

### 6. Safety Features

#### File Access Control

- **Allowlist**: Only files in allowed directories can be accessed
- **Denylist**: Specific paths are blocked (e.g., `.git/`, `node_modules/`)
- **System path protection**: Blocks dangerous system directories

#### Command Execution Safety

- Only allowlisted commands can be executed
- Structured command format (program + args, no raw shell strings)
- Timeout protection for long-running commands
- Output size limits to prevent memory issues

#### Plan Validation

- Validates plans before execution
- Checks for invalid tool usage
- Ensures proper dependencies between steps
- Prevents infinite loops with iteration limits

### 7. Multi-Provider Support

#### Ollama (Local/Offline)

- Runs completely offline
- Uses local Ollama server
- Configurable host and timeout
- Supports multiple models

#### OpenAI (Cloud)

- Automatic fallback when API key is available
- Supports GPT-4, GPT-3.5, and other OpenAI models
- Configurable API endpoint
- Request timeout protection

#### Auto-Detection

- Automatically selects provider based on API key availability
- Can be overridden via CLI flags or configuration

### 8. Repository Awareness

#### Semantic Search

- Builds embedding index of repository files
- Uses vector search to find relevant code
- Supports multiple file types (Ruby, JavaScript, Python, etc.)
- Configurable chunk size and overlap

#### Context Retrieval

- Automatically finds relevant files for tasks
- Prioritizes files based on workspace context
- Combines semantic search with filename matching

### 9. Error Handling & Recovery

#### Graceful Failures

- Handles command failures gracefully
- Provides helpful error messages
- Suggests solutions (e.g., run `--help` for unknown options)

#### Retry Logic

- Automatically retries failed plans
- Learns from previous attempts
- Bounded iteration to prevent infinite loops

#### Fallback Mechanisms

- Falls back to direct file write if diff application fails
- Uses heuristic classification if LLM classification fails
- Provides alternative approaches when primary method fails

### 10. Session Memory

- Remembers conversation context
- Tracks file reads and writes
- Maintains execution history
- Supports multi-turn conversations

### 11. Trace Logging

- Logs all operations to `.devagent/traces.jsonl`
- Structured JSON format for easy parsing
- Includes timestamps and event types
- Useful for debugging and analysis

### 12. Test Integration

- Can run test suites after changes
- Configurable test commands
- Optional test requirement (can be disabled)
- Supports multiple test frameworks (RSpec, Jest, etc.)

---

## Advanced Features

### Command Help Discovery

When a command fails with "unknown option" error, DevAgent:
- Detects the error pattern
- Suggests running the command with `--help`
- Logs the suggestion for the planner to use

### Diff Generation

- Uses unified diff format for all file changes
- Validates diff format before application
- Falls back to direct write if diff fails
- Supports both creation and modification diffs

### Intent Override

- Automatically overrides intent classification for explicit modification requests
- Ensures "modify X" requests are treated as CODE_EDIT even if initially classified as EXPLANATION

### File Search Priority

When searching for files by name:
- **In devagent gem**: Checks `playground/` first, then `lib/`, `src/`, etc.
- **In external projects**: Checks `lib/` first, then `src/`, `app/`, etc.

---

## Configuration Features

### Global vs Project Config

- **Global config** (`~/.devagent.yml`): User preferences, Ollama host
- **Project config** (`.devagent.yml`): Project-specific settings, allowlist/denylist

### Flexible Model Selection

- Different models for different roles (planner, developer, reviewer)
- Configurable temperature and other parameters
- Provider-specific options

### Indexing Configuration

- Configurable file patterns (globs)
- Adjustable chunk size and overlap
- Multi-threaded indexing support

---

## Best Practices

### For Ruby Projects

1. **Use playground/ for testing**: When developing devagent itself, use `playground/` for test files
2. **Follow Ruby conventions**: DevAgent automatically follows Ruby best practices
3. **Let rubocop fix issues**: DevAgent will automatically fix style violations

### For Other Projects

1. **Configure allowlist**: Set up appropriate allowlist in `.devagent.yml`
2. **Set test commands**: Configure test commands for your project
3. **Use specific requests**: Be specific about what you want to create or modify

---

## Limitations

- **Environment dependencies**: Won't install system dependencies (Ruby, Node, etc.)
- **File access restrictions**: Only files in allowlist can be accessed
- **Model limitations**: Smaller models may struggle with complex tasks
- **Iteration bounds**: Strict limits on retries to prevent infinite loops

---

## Future Enhancements

Potential future features:
- Support for more languages and frameworks
- Enhanced error recovery
- Better integration with IDEs
- More sophisticated planning strategies
- Advanced code review capabilities

---

**For more information, see:**
- [README.md](README.md) - Quick start and installation
- [USAGE_GUIDE.md](USAGE_GUIDE.md) - Detailed usage instructions
- [docs/](docs/) - Additional documentation

