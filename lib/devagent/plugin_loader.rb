# frozen_string_literal: true
require_relative "plugin"

module Devagent
  class PluginLoader
    BUILT_INS = %w[rails react ruby_gem].freeze

    def self.load_plugins(ctx)
      load_builtin_plugins
      paths = []
      paths += Dir.glob(File.join(ctx.repo_path, ".devagent/plugins/**/*.rb"))
      paths += Dir.glob(File.expand_path("~/.devagent/plugins/**/*.rb"))

      mods = []
      paths.each { |p| require p }
      ObjectSpace.each_object(Module) do |m|
        next unless m.name&.start_with?("Devagent::")
        next if m == Devagent
        next if m == Devagent::Plugin

        mods << m
      end

      matches = mods.select { |m| m.respond_to?(:applies?) && m.applies?(ctx.repo_path) }
      matches.sort_by { |m| -(m.respond_to?(:priority) ? m.priority : 0) }
    end

    def self.load_builtin_plugins
      BUILT_INS.each do |name|
        require_relative "plugins/#{name}"
      rescue LoadError
        next
      end
    end
  end
end
