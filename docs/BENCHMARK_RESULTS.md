# DevAgent Model Benchmark Results

This document contains the latest benchmark results for Ollama models tested with DevAgent.

## Benchmark Methodology

The benchmark tests four key capabilities:
1. **JSON Schema Compliance** - Ability to generate valid JSON matching a schema (critical for planning)
2. **Diff Discipline** - Ability to generate minimal, correct unified diffs
3. **Stability** - Resistance to hallucination (outputs "BLOCKED" when appropriate)
4. **Latency** - Response time (threshold: <2.5s for local usability)

Run benchmarks: `ruby script/benchmark_models.rb`

## Results Summary

| Rank | Model | Total Score | Latency | JSON | Diff | Stability | Notes |
|------|--------|-------------|---------|------|------|-----------|-------|
| 🥇 | **qwen2.5-coder:1.5b** | **4/4** | 0.57s | ✅ | ✅ | ✅ | **Fastest + reliable** |
| 🥈 | **qwen2.5-coder:7b-instruct-q5_K_M** | **3/4** | 4.6s | ✅ | ✅ | ✅ | **Best quality** |
| 🥉 | **llama3.1:8b-instruct-q4_K_M** | **3/4** | 4.8s | ✅ | ✅ | ✅ | **Strong backup** |
| 4 | **qwen2.5-coder:7b** | **3/4** | 3.7s | ✅ | ✅ | ✅ | Good all-around |
| 5 | **llama3.2:3b** | **3/4** | 2.2s | ✅ | ❌ | ✅ | Fast but fails diff discipline |
| 6 | **deepseek-coder:6.7b** | **3/4** | 1.6s | ✅ | ✅ | ❌ | Fastest large model, fails stability |
| 7 | **mistral:7b-instruct** | **2/4** | 3.1s | ✅ | ❌ | ✅ | Fails diff discipline |
| 8 | **codellama:7b-instruct** | **2/4** | 3.3s | ✅ | ❌ | ✅ | Fails diff discipline |
| 9 | **starcoder2:3b** | **1/4** | Timeout | ❌ | ❌ | ❌ | **Avoid** - timeout issues |

## Detailed Results

### 🥇 qwen2.5-coder:1.5b (Winner)
- **Score**: 4/4
- **Latency**: 0.57s
- **Best for**: Chat, quick explanations, fast autocomplete, simple edits
- **Why it wins**: Perfect balance of speed and reliability. Fastest model while maintaining all quality metrics.

### 🥈 qwen2.5-coder:7b-instruct-q5_K_M (Quality Winner)
- **Score**: 3/4
- **Latency**: 4.6s
- **Best for**: Agent mode, complex refactors, multi-file changes, production code
- **Why it's recommended**: Best quality among larger models. Reliable for complex tasks.

### 🥉 llama3.1:8b-instruct-q4_K_M (Backup)
- **Score**: 3/4
- **Latency**: 4.8s
- **Best for**: Heavy tasks, complex migrations, when 7B models aren't sufficient
- **Why it's useful**: Strong backup option with good all-around performance.

### deepseek-coder:6.7b (Speed Winner for Large Models)
- **Score**: 3/4
- **Latency**: 1.6s
- **Best for**: Fast code generation when you need larger model capabilities
- **Note**: Fails stability test (may hallucinate)

## Recommended Configuration

### For Speed (Default)
```yaml
model: "qwen2.5-coder:1.5b"
planner_model: "qwen2.5-coder:1.5b"
developer_model: "qwen2.5-coder:1.5b"
reviewer_model: "mistral:7b-instruct"
```

### For Quality
```yaml
model: "qwen2.5-coder:7b-instruct-q5_K_M"
planner_model: "qwen2.5-coder:7b-instruct-q5_K_M"
developer_model: "qwen2.5-coder:7b-instruct-q5_K_M"
reviewer_model: "mistral:7b-instruct"
```

### Hybrid (Recommended)
```yaml
model: "qwen2.5-coder:1.5b"  # Fast for most tasks
planner_model: "qwen2.5-coder:1.5b"  # Fast planning
developer_model: "qwen2.5-coder:7b-instruct-q5_K_M"  # Quality code generation
reviewer_model: "mistral:7b-instruct"  # Good for review
```

## Usage Patterns

### Ultra-Fast Chat/Explain (0.57s)
```bash
devagent "Explain this OptionsPricer class"
# Uses: qwen2.5-coder:1.5b
```

### Agent Mode with Quality (4.6s but reliable)
```bash
devagent "Add trailing stop-loss + full RSpec suite"
# Uses: qwen2.5-coder:7b-instruct-q5_K_M (if configured)
```

### Override for Heavy Tasks
```bash
devagent --developer_model llama3.1:8b-instruct-q4_K_M "Migrate to Rails 8"
```

## Benchmark Script

Run benchmarks on all available models:
```bash
ruby script/benchmark_models.rb
```

Benchmark specific models:
```bash
MODELS="qwen2.5-coder:1.5b,qwen2.5-coder:7b-instruct-q5_K_M" ruby script/benchmark_models.rb
```

## Last Updated

Benchmark date: 2025-01-XX
Models tested: 9
Auto-detection: Enabled (filters embedding models)

