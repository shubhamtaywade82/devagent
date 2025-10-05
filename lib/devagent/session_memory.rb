# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Devagent
  # SessionMemory maintains a rolling JSONL conversation log for the current repo.
  class SessionMemory
    attr_reader :path, :limit

    def initialize(repo_path, limit: 20)
      dir = File.join(repo_path, ".devagent")
      FileUtils.mkdir_p(dir)
      @path = File.join(dir, "session.jsonl")
      @limit = limit || 20
      touch!
    end

    def append(role, content)
      write_line(role: role, content: content, timestamp: Time.now.utc.iso8601)
      truncate!
    end

    def last_turns(count = limit)
      read_lines.last(count)
    end

    def clear!
      File.write(path, "")
    end

    private

    def touch!
      FileUtils.touch(path)
    end

    def write_line(payload)
      File.open(path, "a", encoding: "UTF-8") do |file|
        file.puts(JSON.generate(payload))
      end
    end

    def read_lines
      return [] unless File.exist?(path)

      File.readlines(path, chomp: true).filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def truncate!
      lines = read_lines
      return if lines.size <= limit

      slice = lines.last(limit)
      File.open(path, "w", encoding: "UTF-8") do |file|
        slice.each { |payload| file.puts(JSON.generate(payload)) }
      end
    end
  end
end
