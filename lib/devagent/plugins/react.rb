# frozen_string_literal: true

require "json"
require_relative "../plugin"

module Devagent
  module Plugins
    # React plugin configures prompt guidance and test execution for React apps.
    module React
      extend Devagent::Plugin

      def self.applies?(repo)
        pkg = File.join(repo, "package.json")
        return false unless File.exist?(pkg)

        json = begin
          JSON.parse(File.read(pkg))
        rescue StandardError
          {}
        end
        deps = (json["dependencies"] || {}).merge(json["devDependencies"] || {})
        deps.key?("react")
      end

      def self.priority
        90
      end

      def self.on_prompt(_ctx, _task)
        <<~SYS
          You are a senior React engineer.
          - Prefer functional components and hooks.
          - Write Jest/RTL tests for new logic.
          - Keep components small and typed when TS available.
        SYS
      end

      def self.on_action(ctx, name, _args = {})
        case name
        when "react:test"
          if File.exist?(File.join(ctx.repo_path, "yarn.lock"))
            ctx.shell.call("yarn test --watchAll=false", chdir: ctx.repo_path)
          else
            ctx.shell.call("npm test --silent --", chdir: ctx.repo_path)
          end
        end
      end
    end
  end
end
