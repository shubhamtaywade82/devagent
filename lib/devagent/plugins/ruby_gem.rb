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
        return unless name == "gem:test"
        repo = ctx.repo_path
        gemfile = File.join(repo, "Gemfile")
        return nil unless File.exist?(gemfile)

        # Probe rspec
        rspec_ok = system({"BUNDLE_GEMFILE"=>gemfile}, "bash", "-lc", "cd #{Shellwords.escape(repo)} && bundle exec rspec -v > /dev/null 2>&1")
        unless rspec_ok
          # Try to add and init; if that fails, don’t claim a run
          begin
            ctx.shell.call("bundle add rspec", chdir: repo)
            ctx.shell.call("bundle exec rspec --init", chdir: repo)
          rescue
            return nil
          end
        end

        ctx.shell.call("bundle exec rspec --format documentation", chdir: repo)
        true
      end

      def self.rspec_available?(repo)
        begin
          out = `cd #{Shellwords.escape(repo)} && bundle exec rspec -v 2>&1`
          $?.success?
        rescue
          false
        end
      end
    end
  end
end
