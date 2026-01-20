# frozen_string_literal: true

module Devagent
  # SuccessVerifier verifies success criteria against observed reality.
  # This is controller-owned verification; it must not rely on LLM judgment.
  class SuccessVerifier
    def self.verify!(criteria:, observations:, artifacts:)
      Array(criteria).each do |c|
        text = c.to_s.downcase
        case text
        when /test/
          ok = observations.any? do |o|
            type = (o["type"] || o[:type]).to_s
            status = (o["status"] || o[:status]).to_s
            type == "TEST_RESULT" && %w[OK PASS].include?(status)
          end
          raise Error, "Success criteria unmet: tests did not pass" unless ok
        when /file/
          wrote = artifacts[:files_written] && !artifacts[:files_written].empty?
          raise Error, "Success criteria unmet: no files modified" unless wrote
        end
      end
      true
    end
  end
end
