# frozen_string_literal: true

module Devagent
  # Safety guards agent actions against disallowed file targets.
  class Safety
    SYSTEM_DENY_REL = [%r{\A/}, %r{\A~}, %r{\A[a-zA-Z]:}, %r{\A\.\.}].freeze
    SYSTEM_DENY_ABS = [%r{/\.rvm/}, %r{/\.gem/}, %r{/etc/}, %r{/usr/}].freeze

    def initialize(ctx)
      @repo = ctx.repo_path
      @allow = Array(ctx.config.dig("auto", "allowlist"))
      @deny = Array(ctx.config.dig("auto", "denylist"))
      @allow = ["**/*"] if @allow.empty?
    end

    def inside_repo?(relative_path)
      full = absolute_path(relative_path)
      repo_root = File.expand_path(@repo)
      prefix = repo_root.end_with?(File::SEPARATOR) ? repo_root : "#{repo_root}#{File::SEPARATOR}"
      full.start_with?(prefix)
    end

    def allowed?(relative_path)
      return false if SYSTEM_DENY_REL.any? { |regex| relative_path.match?(regex) }
      return false unless inside_repo?(relative_path)

      absolute = absolute_path(relative_path)
      return false if SYSTEM_DENY_ABS.any? { |regex| absolute.match?(regex) }

      allowed = glob_match?(@allow, relative_path)
      denied = glob_match?(@deny, relative_path)
      allowed && !denied
    end

    private

    def glob_match?(patterns, relative_path)
      patterns.any? do |glob|
        # FNM_PATHNAME requires ** to match at least one path separator
        # So "lib/**" matches "lib/a/b" but not "lib/a" directly
        # We need to handle both cases: try with and without FNM_PATHNAME
        File.fnmatch?(glob, relative_path, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
          File.fnmatch?(glob, relative_path, File::FNM_EXTGLOB) ||
          # Also try matching with a wildcard pattern for direct matches
          (glob.end_with?("/**") && File.fnmatch?("#{glob.chomp('/**')}/**/*", relative_path, File::FNM_PATHNAME | File::FNM_EXTGLOB))
      end
    end

    def absolute_path(relative_path)
      File.expand_path(File.join(@repo, relative_path))
    end
  end
end
