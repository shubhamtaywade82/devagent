# frozen_string_literal: true

require "json"
require "time"

module Devagent
  class LearningLog
    LOG_DIR  = ".devagent".freeze
    LOG_FILE = "learning_log.jsonl".freeze

    def self.append(payload)
      Dir.mkdir(LOG_DIR) unless Dir.exist?(LOG_DIR)

      File.open(File.join(LOG_DIR, LOG_FILE), "a") do |f|
        f.puts(payload.merge(timestamp: Time.now.utc.iso8601).to_json)
      end
    rescue StandardError
      # logging must NEVER break execution
      nil
    end
  end
end

