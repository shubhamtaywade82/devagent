# frozen_string_literal: true

require_relative "../plugin"

module Devagent
  module Plugins
    module React
      extend Devagent::Plugin

      def self.applies?(repo)
        File.exist?(File.join(repo, "package.json")) && Dir.glob(File.join(repo, "src", "**", "*.{jsx,tsx}"), File::FNM_EXTGLOB).any?
      end

      def self.priority
        80
      end

      def self.on_prompt(_ctx, _task)
        <<~TEXT
          This is a React project. Use functional components, hooks, and Jest with React Testing Library for tests.
        TEXT
      end

      def self.test_command(ctx)
        File.exist?(File.join(ctx.repo_path, "package.json")) ? "yarn test --watch=false" : nil
      end
    end
  end
end
