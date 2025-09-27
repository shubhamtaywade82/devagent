# frozen_string_literal: true

module Devagent
  # ContextHints heuristically decides when to include repository context in prompts.
  module ContextHints
    KEYWORDS = %w[
      file files class module method function model controller view component spec test rspec
      failing fail error bug fix issue implement update change refactor migrate migration
      config configuration rake task script dependency gem version readme changelog documentation
      docs write build ci pipeline lint formatter stack trace exception
    ].freeze

    LONG_LENGTH_THRESHOLD = 64
    WORD_THRESHOLD = 7

    module_function

    def context_needed?(text)
      return false if text.nil?

      stripped = text.strip
      return false if stripped.empty?

      words = stripped.split
      return true if stripped.length >= LONG_LENGTH_THRESHOLD
      return true if words.length >= WORD_THRESHOLD

      lowered = stripped.downcase
      KEYWORDS.any? { |kw| lowered.include?(kw) }
    end
  end
end
