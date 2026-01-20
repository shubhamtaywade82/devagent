# DevAgent Usage Examples

Practical examples showing how to use DevAgent for real coding tasks.

## Quick Start

```bash
# Start the interactive REPL
./exe/devagent

# Or run a single command
./exe/devagent "your task here"
```

## Example 1: Extending Existing Code

**Scenario**: You have a Calculator class and want to add multiplication and division.

```bash
./exe/devagent
```

Then in the REPL:
```
devagent> add multiply and divide methods to the Calculator class in playground/calculator.rb
```

**What DevAgent does**:
1. Reads the existing `calculator.rb` file
2. Understands the current structure (add/subtract with method chaining)
3. Adds `multiply` and `divide` methods following the same pattern
4. Runs rubocop to ensure code style
5. Shows you the changes before applying

**Expected result**: Calculator now has `multiply(value)` and `divide(value)` methods that return `self` for chaining.

---

## Example 2: Creating a Complete Feature

**Scenario**: Build a simple todo list manager.

```bash
./exe/devagent "create a TodoList class in playground/todo_list.rb with methods to add todos, mark them complete, and list all todos"
```

**What DevAgent does**:
1. Creates `playground/todo_list.rb`
2. Implements a `TodoList` class with:
   - `add(task)` - adds a new todo
   - `complete(index)` - marks a todo as done
   - `list` - returns all todos with their status
3. Follows Ruby best practices (Clean Ruby principles)
4. Adds proper error handling
5. Runs rubocop to ensure style compliance

**Example output structure**:
```ruby
class TodoList
  def initialize
    @todos = []
  end

  def add(task)
    @todos << { task: task, completed: false }
    self
  end

  def complete(index)
    # ... implementation
  end

  def list
    # ... implementation
  end
end
```

---

## Example 3: Writing Tests

**Scenario**: Add tests for the Calculator class.

```bash
./exe/devagent "write RSpec tests for the Calculator class in playground/calculator_spec.rb"
```

**What DevAgent does**:
1. Creates `playground/calculator_spec.rb`
2. Writes comprehensive tests covering:
   - Initialization
   - Addition and subtraction
   - Method chaining
   - Edge cases
3. Uses RSpec best practices with clear contexts
4. Runs the tests to verify they pass

---

## Example 4: Refactoring Code

**Scenario**: Improve code quality in an existing file.

```bash
./exe/devagent "refactor playground/calculator.rb to follow Clean Ruby principles - extract long methods, improve naming, add guard clauses"
```

**What DevAgent does**:
1. Analyzes the current code
2. Identifies areas for improvement:
   - Long methods → splits them
   - Unclear names → renames for clarity
   - Missing guard clauses → adds validation
   - Duplication → extracts common logic
3. Applies refactoring while maintaining functionality
4. Runs rubocop to ensure style
5. Runs any existing tests to verify nothing broke

---

## Example 5: Fixing Bugs

**Scenario**: Calculator division by zero causes an error.

```bash
./exe/devagent "add error handling to the divide method in playground/calculator.rb to prevent division by zero"
```

**What DevAgent does**:
1. Reads the current `divide` method
2. Adds a guard clause to check for zero
3. Raises a descriptive error or handles gracefully
4. Updates tests if they exist
5. Verifies the fix works

**Example fix**:
```ruby
def divide(value)
  raise ArgumentError, "Cannot divide by zero" if value.zero?
  @result /= value
  self
end
```

---

## Example 6: Multi-File Feature

**Scenario**: Create a complete feature with multiple files.

```bash
./exe/devagent "create a simple user authentication system with a User class in playground/user.rb and an Authenticator class in playground/authenticator.rb that can register and login users"
```

**What DevAgent does**:
1. Creates `playground/user.rb` with User class
2. Creates `playground/authenticator.rb` with Authenticator class
3. Ensures both classes work together
4. Follows single responsibility principle
5. Adds proper error handling
6. Runs rubocop on both files

---

## Example 7: Code Explanation

**Scenario**: Understand how existing code works.

```bash
./exe/devagent "explain how the Calculator class works and what design patterns it uses"
```

**What DevAgent does**:
1. Reads and analyzes the Calculator class
2. Explains:
   - The purpose of each method
   - The method chaining pattern
   - How instance variables are used
   - Design principles applied
3. Provides clear, readable explanation

---

## Example 8: Adding Documentation

**Scenario**: Add YARD documentation to existing code.

```bash
./exe/devagent "add YARD documentation comments to all methods in playground/calculator.rb"
```

**What DevAgent does**:
1. Analyzes each method
2. Adds comprehensive YARD comments:
   - Method descriptions
   - Parameter documentation
   - Return value documentation
   - Example usage
3. Follows YARD conventions

---

## Example 9: Code Review and Improvements

**Scenario**: Get suggestions for improving code quality.

```bash
./exe/devagent "review playground/calculator.rb and suggest improvements following Clean Ruby principles"
```

**What DevAgent does**:
1. Analyzes the code structure
2. Identifies:
   - Code smells
   - Potential improvements
   - Best practice violations
   - Refactoring opportunities
3. Provides actionable suggestions
4. Can optionally apply the improvements

---

## Example 10: Complex Refactoring

**Scenario**: Extract a service object from a large class.

```bash
./exe/devagent "extract the calculation logic from Calculator into a separate CalculationService class, keeping Calculator as a thin wrapper"
```

**What DevAgent does**:
1. Analyzes the Calculator class
2. Identifies calculation logic to extract
3. Creates `playground/calculation_service.rb`
4. Refactors Calculator to use the service
5. Maintains the same public API
6. Ensures all functionality still works
7. Updates tests if they exist

---

## Real-World Workflow Example

**Complete workflow for adding a feature**:

```bash
# 1. Start DevAgent
./exe/devagent

# 2. Create the feature
devagent> create a ShoppingCart class in playground/shopping_cart.rb that can add items, remove items, calculate total, and apply discounts

# 3. Review the generated code, then ask for tests
devagent> write RSpec tests for ShoppingCart covering all methods and edge cases

# 4. Run the tests to verify
devagent> run the tests for ShoppingCart

# 5. If something needs fixing
devagent> fix the discount calculation - it should apply percentage discounts correctly

# 6. Get explanation if needed
devagent> explain how the discount system works in ShoppingCart

# 7. Exit when done
devagent> exit
```

---

## Tips for Best Results

1. **Be specific**: "add a method to calculate tax" is better than "improve the code"

2. **Reference files**: "in playground/calculator.rb" helps DevAgent find the right file

3. **State requirements**: "with error handling" or "following Clean Ruby principles" guides the output

4. **Iterate**: Start simple, then refine. "add multiply method" → "now add divide with zero check"

5. **Use the playground**: The `playground/` directory is perfect for experimentation

6. **Review changes**: DevAgent shows diffs before applying - review them!

7. **Run tests**: Always verify with "run tests" or "run rspec" after changes

---

## Common Patterns

### Pattern 1: Add a method to existing class
```
devagent> add a multiply method to Calculator that follows the same pattern as add and subtract
```

### Pattern 2: Create new class with specific methods
```
devagent> create a Logger class in playground/logger.rb with methods: log(message, level), info(message), error(message)
```

### Pattern 3: Refactor for clarity
```
devagent> refactor playground/calculator.rb to use guard clauses and extract the calculation logic
```

### Pattern 4: Add validation
```
devagent> add input validation to Calculator methods to ensure only numeric values are accepted
```

### Pattern 5: Write comprehensive tests
```
devagent> write RSpec tests for Calculator with contexts for each operation and edge cases like division by zero
```

---

## What DevAgent Handles Automatically

✅ **Code style**: Runs rubocop and auto-fixes violations
✅ **File detection**: Knows when to create vs modify files
✅ **Workspace context**: Uses `playground/` for this repo
✅ **Error handling**: Suggests and adds proper error handling
✅ **Best practices**: Follows Ruby conventions and Clean Ruby principles
✅ **Method chaining**: Maintains patterns when extending code
✅ **Test structure**: Uses RSpec contexts and clear descriptions

---

## Limitations to Know

⚠️ **System dependencies**: Won't install Ruby, Bundler, or system packages
⚠️ **File access**: Only works with files in allowlist (see `.devagent.yml`)
⚠️ **Model size**: Smaller models (3B) may struggle with complex multi-step tasks
⚠️ **Git operations**: Read-only git access (status, diff) - no commits

---

## Getting Help

```bash
# Check configuration
./exe/devagent config

# Run diagnostics
./exe/devagent diag

# Test connectivity
./exe/devagent test
```
