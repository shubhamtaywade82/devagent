# frozen_string_literal: true

require "fileutils"
require "json"

module Devagent
  # History manages command history with persistence and deduplication.
  class History
    MAX_HISTORY_SIZE = 1000
    HISTORY_FILENAME = ".devagent/history.json"

    def initialize(repo_path)
      @repo_path = repo_path
      @history_file = File.join(repo_path, HISTORY_FILENAME)
      @history = load_history
    end

    def add(command)
      return if command.nil? || command.strip.empty?

      # Remove duplicates (case-insensitive)
      @history.delete_if { |entry| entry.strip.downcase == command.strip.downcase }
      # Add to end (most recent)
      @history << command.strip
      # Keep only last MAX_HISTORY_SIZE entries
      @history = @history.last(MAX_HISTORY_SIZE)
      save_history
    end

    def entries
      # Return in chronological order (oldest first) for TTY::Reader
      # TTY::Reader navigates backwards from the end, so the most recent
      # command will be shown first when pressing up arrow
      @history.dup
    end

    def load_history
      return [] unless File.exist?(@history_file)

      JSON.parse(File.read(@history_file, encoding: "UTF-8"))
    rescue JSON::ParserError, Errno::ENOENT
      []
    end

    def save_history
      FileUtils.mkdir_p(File.dirname(@history_file))
      File.write(@history_file, JSON.pretty_generate(@history), encoding: "UTF-8")
    rescue StandardError
      # Silently fail if we can't write history
    end
  end
end
