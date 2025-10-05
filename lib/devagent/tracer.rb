# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Devagent
  # Tracer writes structured JSONL events for debugging agent runs.
  class Tracer
    attr_reader :path

    def initialize(repo_path)
      dir = File.join(repo_path, ".devagent")
      FileUtils.mkdir_p(dir)
      @path = File.join(dir, "traces.jsonl")
    end

    def event(type, payload = {})
      append(type: type, payload: payload, timestamp: Time.now.utc.iso8601)
    end

    def debug(message)
      event("debug", message: message)
    end

    private

    def append(record)
      File.open(path, "a", encoding: "UTF-8") do |file|
        file.puts(JSON.generate(record))
      end
    rescue StandardError
      # tracing should never crash the agent
      nil
    end
  end
end
