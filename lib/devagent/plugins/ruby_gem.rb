# frozen_string_literal: true

require_relative "../plugin"

module Devagent
  module Plugins
    # RubyGem plugin adds conventions for Ruby library projects.
    module RubyGem
      extend Devagent::Plugin

      def self.applies?(repo)
        Dir.glob(File.join(repo, "*.gemspec")).any?
      end

      def self.priority
        80
      end

      def self.on_prompt(_ctx, _task)
        <<~SYS
          You are a senior Ruby library author.
          - Maintain semantic versioning and update CHANGELOG.
          - Provide thorough RSpec with boundary tests.
        SYS
      end

      def self.on_action(ctx, name, _args = {})
        case name
        when "gem:test"
          ctx.shell.call("bundle exec rspec", chdir: ctx.repo_path)
        end
      end
    end
  end
end
