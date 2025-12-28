# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  add_filter "/exe/"
  add_filter "/bin/"
  add_filter "/lib/devagent/ui/"
  add_filter "/lib/devagent/llm/"
  add_filter "/lib/devagent/ollama.rb"
  minimum_coverage 80
end

require "devagent"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
