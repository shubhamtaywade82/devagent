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

      def self.on_index(ctx)
        ctx.index # (could add ignore rules here)
      end

      def self.on_prompt(_ctx, _task)
        <<~SYS
          You are a senior Ruby on Rails engineer.
          - Follow Rails MVC conventions and strong params.
          - Ensure migrations are reversible.
          - Generate/maintain RSpec tests under spec/.
          - Return unified diffs for small edits, or whole file content for replacements.
        SYS
      end

      def self.on_action(ctx, name, _args = {})
        case name
        when "rails:test"
          ctx.shell.call("bundle exec rspec --format documentation", chdir: ctx.repo_path)
        end
      end
    end
  end
end
