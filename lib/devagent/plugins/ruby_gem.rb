# frozen_string_literal: true

require_relative "../plugin"

module Devagent
  module Plugins
    module RubyGem
      extend Devagent::Plugin

      def self.applies?(repo)
        File.exist?(File.join(repo, "devagent.gemspec")) || Dir.glob(File.join(repo, "*.gemspec")).any?
      end

      def self.priority
        60
      end

      def self.on_prompt(_ctx, _task)
        <<~TEXT
          This is a Ruby gem project. Maintain semantic versioning and prefer RSpec for tests.
        TEXT
      end

      def self.test_command(_ctx)
        "bundle exec rspec"
      end
    end
  end
end
