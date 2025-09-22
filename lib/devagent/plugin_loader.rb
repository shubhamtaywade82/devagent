# frozen_string_literal: true

require_relative "plugin"

module Devagent
  # PluginLoader discovers built-in and user-provided plugins.
  class PluginLoader
    BUILT_INS = %w[rails react ruby_gem].freeze
    EXCLUDED_MODS = [Devagent, Devagent::Plugin].freeze

    def self.load_plugins(ctx)
      load_builtin_plugins
      require_paths(plugin_paths(ctx.repo_path))
      matching_plugins(ctx.repo_path)
        .sort_by { |mod| -(mod.respond_to?(:priority) ? mod.priority : 0) }
    end

    def self.load_builtin_plugins
      BUILT_INS.each do |name|
        require_relative "plugins/#{name}"
      rescue LoadError
        next
      end
    end

    def self.require_paths(paths)
      paths.each { |path| require path }
    end
    private_class_method :require_paths

    def self.plugin_paths(repo_path)
      repo_plugins = Dir.glob(File.join(repo_path, ".devagent/plugins/**/*.rb"))
      user_plugins = Dir.glob(File.expand_path("~/.devagent/plugins/**/*.rb"))
      repo_plugins + user_plugins
    end
    private_class_method :plugin_paths

    def self.matching_plugins(repo_path)
      ObjectSpace.each_object(Module).each_with_object([]) do |mod, matches|
        next unless plugin_candidate?(mod)
        next unless mod.applies?(repo_path)

        matches << mod
      end
    end
    private_class_method :matching_plugins

    def self.plugin_candidate?(mod)
      return false unless mod.name&.start_with?("Devagent::")
      return false if EXCLUDED_MODS.include?(mod)
      return false unless mod.respond_to?(:applies?)

      true
    end
    private_class_method :plugin_candidate?
  end
end
