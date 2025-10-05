# frozen_string_literal: true

require_relative "../plugin"

module Devagent
  module Plugins
    module Rails
      extend Devagent::Plugin

      def self.applies?(repo)
        File.exist?(File.join(repo, "bin", "rails")) && File.exist?(File.join(repo, "config", "application.rb"))
      end

      def self.priority
        100
      end

      def self.on_load(context)
        context.tracer.event("plugin", name: "rails")
      end

      def self.on_prompt(_ctx, _task)
        <<~TEXT
          You are working in a Ruby on Rails application. Follow MVC conventions, ensure migrations are reversible, and prefer RSpec for tests.
        TEXT
      end

      def self.test_command(_ctx)
        "bundle exec rspec"
      end
    end
  end
end
