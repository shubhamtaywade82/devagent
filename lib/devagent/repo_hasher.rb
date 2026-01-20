# frozen_string_literal: true

require "digest"

module Devagent
  class RepoHasher
    def self.current(repo_path = Dir.pwd)
      # Exclude common directories that shouldn't affect repo state
      exclude_patterns = %w[.git node_modules log tmp dist build coverage .devagent]

      files = Dir.glob(File.join(repo_path, "**/*"), File::FNM_DOTMATCH)
                 .reject { |f| File.directory?(f) }
                 .reject { |f| exclude_patterns.any? { |pattern| f.include?(pattern) } }
                 .sort

      digest = Digest::SHA256.new
      files.each do |file|
        relative_path = file.sub(%r{^#{Regexp.escape(repo_path)}/?}, "")
        digest.update(relative_path)
        begin
          content = File.read(file)
          digest.update(content)
        rescue StandardError
          # Skip files that can't be read (permissions, etc.)
          nil
        end
      end

      digest.hexdigest
    end
  end
end
