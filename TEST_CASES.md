# DevAgent Test Cases

This document provides comprehensive test cases to exercise different DevAgent features and verify that everything works as expected.

---

## Test Cases by Intent Type

### 1. CODE_EDIT - File Creation & Modification

#### Simple File Creation

```bash
# Ruby
exe/devagent "Create a todo list manager class in Ruby"
exe/devagent "Create a simple HTTP client in Python"
exe/devagent "Create a user authentication module in JavaScript"
```

#### Modifying Existing Files

```bash
exe/devagent "Add a multiply method to the calculator class"
exe/devagent "Add error handling to the hello_world.rb file"
exe/devagent "Add a divide method to calculator.rb that handles division by zero"
```

#### Refactoring

```bash
exe/devagent "Refactor calculator.rb to use a module for operations"
exe/devagent "Extract the greeting logic from hello_world.rb into a separate method"
```

#### Multi-File Operations

```bash
exe/devagent "Create a test file for calculator.rb using RSpec"
exe/devagent "Create a README.md explaining how to use the calculator"
```

---

### 2. CODE_REVIEW - Code Analysis

```bash
exe/devagent "Review the calculator.rb file for code quality"
exe/devagent "Check if calculator.rb follows Ruby best practices"
exe/devagent "Audit playground/hello_world.rb for potential improvements"
```

---

### 3. DEBUG - Error Fixing

```bash
# First create a file with intentional errors
exe/devagent "Create a broken Ruby file with syntax errors in playground/broken.rb"

# Then fix it
exe/devagent "Fix the syntax errors in playground/broken.rb"
```

---

### 4. EXPLANATION - Information Queries

```bash
exe/devagent "What does the calculator.rb file do?"
exe/devagent "Explain how the HelloWorld class works"
exe/devagent "How does the intent classification work in this codebase?"
exe/devagent "What is the purpose of the orchestrator?"
```

---

### 5. Advanced Features

#### Complex OOP Patterns

```bash
exe/devagent "Create a factory pattern implementation in Ruby"
exe/devagent "Create a singleton pattern example in playground"
exe/devagent "Create a decorator pattern implementation"
```

#### Design Patterns

```bash
exe/devagent "Create a REST API client class with error handling"
exe/devagent "Create a logger class with different log levels"
exe/devagent "Create a configuration manager using a builder pattern"
```

#### Testing

```bash
exe/devagent "Create RSpec tests for calculator.rb"
exe/devagent "Add unit tests for all calculator methods"
```

#### Documentation

```bash
exe/devagent "Add YARD documentation to calculator.rb"
exe/devagent "Create API documentation for the calculator class"
```

#### File Operations

```bash
exe/devagent "Create a JSON configuration file for the calculator"
exe/devagent "Create a YAML config file for application settings"
exe/devagent "Create a .env.example file with required environment variables"
```

---

### 6. Edge Cases & Error Handling

#### Invalid Requests (Should be Rejected Gracefully)

```bash
exe/devagent "Delete all files in the repository"
exe/devagent "Modify /etc/passwd"
```

#### Vague Requests (Should Ask for Clarification)

```bash
exe/devagent "Improve the code"
exe/devagent "Fix the bug"
```

#### Complex Multi-Step Tasks

```bash
exe/devagent "Create a complete user management system with CRUD operations"
exe/devagent "Create a shopping cart system with add, remove, and checkout methods"
```

---

### 7. Language-Specific Tests

#### Ruby

```bash
exe/devagent "Create a Ruby gem structure with lib/ and spec/ directories"
exe/devagent "Create a Ruby class with metaprogramming"
```

#### JavaScript/TypeScript

```bash
exe/devagent "Create a TypeScript interface for a User model"
exe/devagent "Create a React component for a button"
```

#### Python

```bash
exe/devagent "Create a Python class with type hints"
exe/devagent "Create a Python decorator for caching"
```

---

### 8. Integration Tests

#### Full Workflow

```bash
# Create a feature
exe/devagent "Create a bank account class with deposit and withdraw methods"

# Add tests
exe/devagent "Create RSpec tests for the bank account class"

# Add documentation
exe/devagent "Add YARD documentation to the bank account class"

# Review it
exe/devagent "Review the bank account implementation for security issues"
```

---

## Quick Test Script

You can create a test script to run multiple tests:

```bash
# Create a test file
cat > test_devagent.sh << 'EOF'
#!/bin/bash

echo "=== Test 1: Create Calculator ==="
exe/devagent "Create a calculator using OOPs in ruby"

echo -e "\n=== Test 2: Add Method ==="
exe/devagent "Add a multiply method to calculator.rb"

echo -e "\n=== Test 3: Explanation ==="
exe/devagent "What does calculator.rb do?"

echo -e "\n=== Test 4: Code Review ==="
exe/devagent "Review calculator.rb for improvements"

echo -e "\n=== Test 5: Create Tests ==="
exe/devagent "Create RSpec tests for calculator.rb"
EOF

chmod +x test_devagent.sh
./test_devagent.sh
```

---

## What to Observe

For each test, check:

1. **Intent Classification** — Correct intent type (CODE_EDIT, CODE_REVIEW, EXPLANATION, etc.)
2. **Plan Generation** — Logical steps with proper dependencies
3. **File Operations** — Correct paths (playground/ for devagent gem, standard directories for other projects)
4. **Rubocop Integration** — Auto-fixes violations automatically
5. **Error Handling** — Graceful failures with helpful messages
6. **Code Quality** — Follows best practices (frozen_string_literal, documentation, etc.)
7. **Dependencies** — Correct step dependencies (read before write)
8. **Workspace Detection** — Uses appropriate directories based on context

---

## Expected Behaviors

### For CODE_EDIT Tasks

- ✅ Creates or modifies files as requested
- ✅ Follows language-specific best practices
- ✅ Runs rubocop (for Ruby) and auto-fixes violations
- ✅ Verifies fixes with final rubocop check
- ✅ Uses correct workspace directory (playground/ for devagent gem)

### For CODE_REVIEW Tasks

- ✅ Analyzes code quality
- ✅ Provides constructive feedback
- ✅ Suggests improvements
- ✅ Identifies potential issues

### For EXPLANATION Tasks

- ✅ Reads relevant files
- ✅ Provides clear explanations
- ✅ Uses semantic search to find context
- ✅ No file modifications

### For DEBUG Tasks

- ✅ Identifies the problem
- ✅ Proposes a fix
- ✅ Applies the fix
- ✅ Verifies the solution

---

## Testing Checklist

When running tests, verify:

- [ ] Intent is classified correctly
- [ ] Plan has logical steps
- [ ] File paths are correct (playground/ for devagent gem)
- [ ] Rubocop runs and fixes violations
- [ ] Code follows best practices
- [ ] Dependencies are correct
- [ ] Error messages are helpful
- [ ] Retries work when needed
- [ ] Final code passes all checks

---

## Troubleshooting Test Failures

### Plan Rejection

**Symptom**: `PLAN_REJECTED: ...`

**Possible Causes**:
- Confidence too low
- Invalid tool usage
- Missing dependencies
- File path issues

**Solution**: Be more specific in your request, check file paths

### Step Failures

**Symptom**: `Step N failed: ...`

**Possible Causes**:
- Command execution error
- File not found
- Dependency not satisfied
- Permission issues

**Solution**: Check error message, verify file exists, check permissions

### Rubocop Issues

**Symptom**: Rubocop violations not fixed

**Possible Causes**:
- Rubocop -a step missing
- Non-auto-correctable violations
- Rubocop not configured

**Solution**: Check plan includes rubocop -a step, manually fix remaining issues

### Workspace Issues

**Symptom**: Files created in wrong directory

**Possible Causes**:
- Workspace detection not working
- Configuration issue

**Solution**: Verify devagent_gem? detection, check configuration

---

## Continuous Testing

For continuous integration, you can run a subset of tests:

```bash
# Quick smoke test
exe/devagent "Create a simple hello world class in Ruby"
exe/devagent "What does the hello world class do?"

# Full test suite (run manually)
./test_devagent.sh
```

---

## Contributing Test Cases

When adding new features, add corresponding test cases to this document to ensure:
- The feature works as expected
- Edge cases are handled
- Error messages are helpful
- Integration with other features works

---

**See Also:**
- [USAGE_GUIDE.md](USAGE_GUIDE.md) - Detailed usage instructions
- [FEATURES.md](FEATURES.md) - Feature documentation
- [docs/QA_PROMPT_SUITE.md](docs/QA_PROMPT_SUITE.md) - QA test suite

