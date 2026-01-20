# frozen_string_literal: true

require "shellwords"

module Devagent
  class GitDiff
    def self.current(repo_path = Dir.pwd)
      return nil unless system("cd #{repo_path.shellescape} && git rev-parse --is-inside-work-tree > /dev/null 2>&1")

      Dir.chdir(repo_path) do
        `git diff`
      end
    rescue StandardError
      nil
    end
  end
end
