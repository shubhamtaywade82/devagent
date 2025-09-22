# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in devagent.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"

require "logger"

def initialize(ctx)
  @ctx = ctx
  @executor = Executor.new(ctx)
  @max_iter = ctx.config.dig("auto", "max_iterations") || 3
  @require_green = ctx.config.dig("auto", "require_tests_green") != false
  @threshold = ctx.config.dig("auto", "confirmation_threshold") || 0.7
  @logger = Logger.new(File.join(ctx.repo_path, "devagent.log"))

  # build index once, allow plugins to tune it
  ctx.plugins.each { |p| p.on_index(ctx) if p.respond_to?(:on_index) }
  ctx.index.build!
end

