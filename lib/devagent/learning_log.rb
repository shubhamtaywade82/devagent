# frozen_string_literal: true

require "json"
require "time"

module Devagent
  class LearningLog
    LOG_DIR  = ".devagent"
    LOG_FILE = "learning_log.jsonl"

    def self.append(payload)
      FileUtils.mkdir_p(LOG_DIR)

      File.open(File.join(LOG_DIR, LOG_FILE), "a") do |f|
        f.puts(payload.merge(timestamp: Time.now.utc.iso8601).to_json)
      end
    rescue StandardError
      # logging must NEVER break execution
      nil
    end
  end
end
