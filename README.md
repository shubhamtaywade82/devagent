# Devagent

Devagent is a local-first, autonomous coding agent for Ruby projects. It plans tasks, edits files, writes tests, and iterates on its own while respecting sandboxed file access. The agent can run fully offline through Ollama or switch to OpenAI models when an `OPENAI_API_KEY` is available.

## Features

- ✅ Multi-provider LLM adapters (Ollama + OpenAI) with automatic fallback based on the presence of `OPENAI_API_KEY`.
- ✅ Repository-aware retrieval using embeddings stored in a SQLite vector index with backend metadata checks.
- ✅ Planner → Developer → Tester → Reviewer loop that validates JSON tool calls before execution.
- ✅ Safe ToolBus with allow/deny path globs, git safeguards, and streaming output from tool executions.
- ✅ Session memory, trace logging, prompt templates, and plugin hooks for Rails, React, and Ruby gem projects.

## Quickstart

```bash
# Install dependencies
bundle install

# Install gem locally
bundle exec rake install

# Start the autonomous REPL
devagent

# Force a specific provider
OPENAI_API_KEY=sk-... devagent --provider openai --model gpt-4o-mini
```

### Ollama host configuration (directory-independent)

Devagent resolves the Ollama host in this priority order:

1. **CLI flag**: `--ollama-host`
2. **Environment variable**: `OLLAMA_HOST`
3. **User config file**: `~/.devagent.yml`
4. **Default**: `http://localhost:11434`

Examples:

```bash
# One-off override
devagent start --provider ollama --ollama-host http://192.168.1.14:11434

# Environment variable (recommended for most users)
export OLLAMA_HOST=http://192.168.1.14:11434
devagent start --provider ollama
```

User config (`~/.devagent.yml`):

```yaml
ollama:
  host: http://192.168.1.14:11434
  timeout: 60
```

Inspect resolved configuration:

```bash
devagent config
devagent diag
```

### Configuration (`.devagent.yml`)

```yaml
provider: auto # auto|openai|ollama
model: gpt-4o-mini
planner_model: gpt-4o-mini
developer_model: gpt-4o-mini
reviewer_model: gpt-4o
embed_model: text-embedding-3-small
openai:
  uri_base: "https://api.openai.com/v1" # Point to Ollama's /v1 to proxy through ruby-openai
  api_key_env: "OPENAI_API_KEY"
  request_timeout: 600
  params:
    temperature: 0.2
    top_p: 0.95
  options:
    num_gpu: 0
    num_ctx: 2048
ollama:
  host: "http://localhost:11434"
  timeout: 300
  params:
    temperature: 0.2
    top_p: 0.95
auto:
  max_iterations: 3
  require_tests_green: true
  dry_run: false
  allowlist:
    - "app/**"
    - "lib/**"
    - "spec/**"
    - "config/**"
    - "db/**"
    - "src/**"
  denylist:
    - ".git/**"
    - "node_modules/**"
    - "log/**"
    - "tmp/**"
    - "dist/**"
    - "build/**"
    - ".env*"
    - "config/credentials*"
index:
  globs:
    - "**/*.{rb,ru,erb,haml,slim,js,jsx,ts,tsx}"
  chunk_size: 1800
  overlap: 200
  threads: 8
memory:
  short_term_turns: 20
```

## CLI Commands

| Command                                          | Description                                                           |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| `devagent`                                       | Launch the interactive REPL (default task).                           |
| `devagent --provider openai --model gpt-4o-mini` | Override provider/model for a session.                                |
| `devagent start --ollama-host http://...`        | Override Ollama host for a session.                                   |
| `devagent config`                                | Print resolved configuration (including Ollama host + source).        |
| `devagent diag`                                  | Print provider, model, embedding backend, and key status diagnostics. |
| `devagent test`                                  | Run connectivity diagnostics.                                         |

## Tooling & Scripts

- `script/audit_devagent.rb` — static audit that checks repository structure and configuration, printing ✅/⚠️/❌ status.
- `script/smoke.rb` — runs a lightweight LLM smoke test using the configured planner adapter.
- `script/ollama_openai_smoke.rb` — verifies ruby-openai connectivity in both non-streaming and streaming modes.

Run the audit locally:

```bash
ruby script/audit_devagent.rb
```

Run the smoke test with either provider:

```bash
# OpenAI
OPENAI_API_KEY=sk-... ruby script/smoke.rb

# Ollama (ensure `ollama serve` is running)
ruby script/smoke.rb

# Ollama via OpenAI-compatible endpoint
OPENAI_API_KEY=ollama ruby script/ollama_openai_smoke.rb
```

## Requirements

- Ruby 3.2+
- Bundler & Git
- SQLite (for embeddings store)
- Optional Node.js for front-end/Jest tooling
- Ollama running at `http://localhost:11434` for offline mode, or an OpenAI API key for cloud mode

## Development

After cloning the repo:

```bash
bundle install
bundle exec rake spec
```

The project uses RSpec for tests and ships with a GitHub Actions workflow that runs the static audit and specs. Run `bundle exec rake install` to install the gem locally and `bundle exec rake release` to publish new versions.

## License

Released under the [MIT License](LICENSE.txt).
