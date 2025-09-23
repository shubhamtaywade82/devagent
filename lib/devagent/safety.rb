# frozen_string_literal: true

module Devagent
  class Safety
    def initialize(ctx)
      @repo = ctx.repo_path
      @allow = Array(ctx.config.dig("auto", "allowlist") || ["**/*"])
      @deny  = Array(ctx.config.dig("auto", "denylist")  || ["node_modules/**", ".git/**", "tmp/**", "log/**"])
    end

    def allowed?(relative_path)
      return false unless inside_repo?(relative_path)
      full = File.join(@repo, relative_path)
      allowed = @allow.any? { |glob| File.fnmatch?(File.join(@repo, glob), full, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      denied  = @deny.any?  { |glob| File.fnmatch?(File.join(@repo, glob), full, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      allowed && !denied
    end

    private

    def inside_repo?(rel)
      full = File.expand_path(File.join(@repo, rel))
      root = File.expand_path(@repo)
      prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
      full.start_with?(prefix)
    end
  end
end
