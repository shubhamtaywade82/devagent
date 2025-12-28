# frozen_string_literal: true

require_relative "lib/devagent/version"

Gem::Specification.new do |spec|
  spec.name = "devagent"
  spec.version = Devagent::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary               = "Autonomous local AI coding agent (Ollama) for repo-aware planning, edits, and tests."
  spec.description           = <<~DESC.strip
    devagent is a CLI that acts like a senior developer: it plans tasks, edits/creates files, generates/updates RSpec, runs
    tests, and iterates—fully locally via Ollama. Framework-aware via a plugin system (Rails, React, Ruby gems).
  DESC
  spec.homepage              = "https://github.com/shubhamtaywade/devagent"
  spec.license               = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/shubhamtaywade/devagent",
    "changelog_uri" => "https://github.com/shubhamtaywade/devagent/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/shubhamtaywade/devagent/issues",
    "rubygems_mfa_required" => "true"
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # === Runtime dependencies (keep light) ===
  spec.add_dependency "diffy", "~> 3.4"
  spec.add_dependency "dotenv", "~> 2.8"
  spec.add_dependency "json-schema", "~> 4.3"
  spec.add_dependency "paint", "~> 2.2"
  spec.add_dependency "parallel", "~> 1.24"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "ruby-openai", "~> 5.0"
  spec.add_dependency "sqlite3", "~> 1.7"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-box", "~> 0.7"
  spec.add_dependency "tty-color", "~> 0.6"
  spec.add_dependency "tty-command", "~> 0.10"
  spec.add_dependency "tty-config", "~> 0.6"
  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "tty-logger", "~> 0.6"
  spec.add_dependency "tty-markdown", "~> 0.7"
  spec.add_dependency "tty-progressbar", "~> 0.18"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-reader", "~> 0.9"
  spec.add_dependency "tty-screen", "~> 0.8"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # === Development/test dependencies ===
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.66"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
