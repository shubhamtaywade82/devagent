# frozen_string_literal: true

module Devagent
  # Safety guards agent actions against disallowed file targets.
  class Safety
    def initialize(ctx)
      @repo = ctx.repo_path
      @allow = ctx.config.dig("auto", "allowlist") || ["**/*"]
      @deny = ctx.config.dig("auto", "denylist") || []
    end

    def inside_repo?(relative_path)
      full = File.expand_path(File.join(@repo, relative_path))
      repo_root = File.expand_path(@repo)
      prefix = repo_root.end_with?(File::SEPARATOR) ? repo_root : "#{repo_root}#{File::SEPARATOR}"
      full.start_with?(prefix)
    end

    def allowed?(relative_path)
      return false unless inside_repo?(relative_path)

      full_path = File.join(@repo, relative_path)
      allowed = @allow.any? { |glob| File.fnmatch?(File.join(@repo, glob), full_path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      denied = @deny.any? { |glob| File.fnmatch?(File.join(@repo, glob), full_path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      allowed && !denied
    end
  end
end
