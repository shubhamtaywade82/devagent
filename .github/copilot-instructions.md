# Copilot Instructions for Devagent

Welcome to the Devagent codebase! This document provides essential guidelines for AI coding agents to be productive in this project. Please follow these instructions to ensure consistency and alignment with the project's architecture and conventions.

## Project Overview
Devagent is a Ruby gem. The primary code resides in the `lib/` directory, with the main entry point being `lib/devagent.rb`. The gem's purpose and functionality are currently under development, as indicated by placeholders in the README.

### Key Components
- **`lib/devagent.rb`**: The main entry point for the gem.
- **`lib/devagent/version.rb`**: Manages the gem's versioning.
- **`bin/console`**: Provides an interactive Ruby console for experimenting with the gem's code.
- **`bin/setup`**: Sets up the development environment by installing dependencies.
- **`spec/`**: Contains RSpec tests for the gem.

## Development Workflow
1. **Setup**: Run `bin/setup` to install dependencies.
2. **Testing**: Use `rake spec` to run the test suite.
3. **Interactive Console**: Run `bin/console` to experiment with the gem's code interactively.
4. **Local Installation**: Use `bundle exec rake install` to install the gem locally.
5. **Releasing**: Update the version in `lib/devagent/version.rb` and run `bundle exec rake release` to release a new version.

## Project-Specific Conventions
- Follow the Ruby community's best practices for gem development.
- Use RSpec for testing. Tests are located in the `spec/` directory.
- Maintain semantic versioning in `lib/devagent/version.rb`.

## External Dependencies
- **Bundler**: Used for managing dependencies.
- **RSpec**: Used for testing.

## Examples
- To run the tests:
  ```bash
  rake spec
  ```
- To experiment with the gem interactively:
  ```bash
  bin/console
  ```
- To release a new version:
  ```bash
  bundle exec rake release
  ```

## Notes for AI Agents
- Ensure all changes are tested using RSpec.
- Adhere to the development workflow and conventions outlined above.
- Reference the README for additional context on the gem's purpose and usage.

For any questions or clarifications, consult the project maintainers or the contributing guidelines in `CODE_OF_CONDUCT.md`.