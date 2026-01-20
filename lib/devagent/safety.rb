# frozen_string_literal: true

module Devagent
  # Safety guards agent actions against disallowed file targets.
  class Safety
    SYSTEM_DENY_REL = [%r{\A/}, /\A~/, /\A[a-zA-Z]:/].freeze
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
      original_path = relative_path.to_s.strip

      # Block absolute system paths, home directory, and Windows drive letters at the start
      # Check the original path before normalization to catch absolute paths
      return false if SYSTEM_DENY_REL.any? { |regex| original_path.match?(regex) }

      # Normalize path: remove ./ prefix and handle leading /
      normalized = normalize_path(relative_path)

      # Resolve to absolute path for system path checks
      absolute = absolute_path(normalized)

      # Block dangerous system directories (check the resolved absolute path)
      return false if SYSTEM_DENY_ABS.any? { |regex| absolute.match?(regex) }

      # Additional check: block if path resolves to a dangerous system location
      # even if it started with ../
      dangerous_system_dirs = %w[/etc /usr /var /tmp /opt /root /bin /sbin /lib /sys /proc /dev /mnt /media /boot /srv]
      return false if dangerous_system_dirs.any? { |dir| absolute.start_with?("#{dir}/") || absolute == dir }

      # For paths inside repo, check allowlist/denylist
      # For paths outside repo, allow by default (only system paths are blocked above)
      return true unless inside_repo?(normalized)

      allowed = glob_match?(@allow, normalized)
      denied = glob_match?(@deny, normalized)
      allowed && !denied

      # Path is outside repo - allow it (system paths already blocked above)
    end

    private

    def normalize_path(relative_path)
      path = relative_path.to_s.strip
      return path if path.empty?

      # Remove ./ prefix (common relative path notation)
      path = path.delete_prefix("./")

      # If path starts with /, it might be:
      # 1. An absolute system path (should be rejected)
      # 2. A relative path meant to be at repo root (should be normalized)
      # We normalize it if removing the leading / would result in a path inside the repo
      if path.start_with?("/")
        # Check if it's clearly a system path - reject these
        system_paths = %w[/etc /usr /var /tmp /opt /home /root /bin /sbin /lib /sys /proc /dev /mnt /media]
        return path if system_paths.any? { |sys| path.start_with?("#{sys}/") || path == sys }

        # Try normalizing: remove leading / and check if it would be inside repo
        test_path = path.delete_prefix("/")
        test_absolute = absolute_path(test_path)
        repo_root = File.expand_path(@repo)
        # Only normalize if the test path would be inside the repo
        path = test_path if test_absolute.start_with?(repo_root)
      end

      path
    end

    def glob_match?(patterns, relative_path)
      patterns.any? do |glob|
        # FNM_PATHNAME requires ** to match at least one path separator
        # So "lib/**" matches "lib/a/b" but not "lib/a" directly
        # We need to handle both cases: try with and without FNM_PATHNAME
        File.fnmatch?(glob, relative_path, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
          File.fnmatch?(glob, relative_path, File::FNM_EXTGLOB) ||
          # Also try matching with a wildcard pattern for direct matches
          (glob.end_with?("/**") && File.fnmatch?("#{glob.chomp("/**")}/**/*", relative_path, File::FNM_PATHNAME | File::FNM_EXTGLOB))
      end
    end

    def absolute_path(relative_path)
      File.expand_path(File.join(@repo, relative_path))
    end
  end
end
