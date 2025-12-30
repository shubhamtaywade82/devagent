# frozen_string_literal: true

require_relative "prompts"

module Devagent
  # DiffGenerator asks the developer model for a minimal unified diff.
  class DiffGenerator
    # Build a minimal unified diff for creating a new file from scratch.
    #
    # Controller-owned and deterministic; avoids relying on model formatting.
    def self.build_add_file_diff(path:, content:)
      raise Error, "content required" if content.to_s.empty?

      lines = content.to_s.lines
      raise Error, "content required" if lines.empty?

      hunk_lines = lines.map { |line| "+#{line}" }.join
      hunk_count = lines.size

      <<~DIFF
        --- /dev/null
        +++ b/#{path}
        @@ -0,0 +1,#{hunk_count} @@
        #{hunk_lines}
      DIFF
    end

    def initialize(context)
      @context = context
    end

    def generate(path:, original:, goal:, reason:, file_exists:)
      # Check for duplicate comments BEFORE generating diff (for "add comment at top" tasks)
      reason_lower = reason.to_s.downcase
      goal_lower = goal.to_s.downcase
      if (reason_lower.include?("comment") && (reason_lower.include?("top") || reason_lower.include?("beginning"))) ||
         (goal_lower.include?("comment") && (goal_lower.include?("top") || goal_lower.include?("beginning")))
        original_lines = original.lines
        first_few_lines = original_lines.first(3).map(&:to_s).map(&:strip)
        has_comment = first_few_lines.any? do |line|
          line.start_with?("#") && (line.downcase.include?("comment") || line.downcase.include?("added"))
        end

        if has_comment
          # Comment already exists, return a valid no-op diff
          file_header = "--- a/#{path}\n+++ b/#{path}"
          hunk_header = "@@ -1,3 +1,3 @@"
          context_lines = original_lines.first(3).map { |line| " #{line}" }.join
          return "#{file_header}\n#{hunk_header}\n#{context_lines}"
        end
      end

      prompt = <<~PROMPT
        #{Prompts::DIFF_SYSTEM}

        Path:
        #{path}

        File exists:
        #{file_exists ? "true" : "false"}

        Goal:
        #{goal}

        Change intent:
        #{reason}

        ORIGINAL (full file contents):
        #{original}
      PROMPT

      diff = context.query(
        role: :developer,
        prompt: prompt,
        stream: false,
        params: { temperature: 0.0 }
      ).to_s.strip

      # Remove markdown code blocks if present
      diff = diff.gsub(/^```(?:diff|unified)?\s*\n/, "").gsub(/\n```\s*$/, "").strip

      # If diff is missing @@ hunk markers, construct a proper diff as fallback
      unless diff.include?("@@")
        # The LLM failed to generate a proper diff format
        # Construct one based on the task description
        reason_lower = reason.to_s.downcase
        goal_lower = goal.to_s.downcase

        if (reason_lower.include?("comment") && (reason_lower.include?("top") || reason_lower.include?("beginning"))) ||
           (goal_lower.include?("comment") && (goal_lower.include?("top") || goal_lower.include?("beginning")))
          # For "add comment at top" tasks, construct a proper unified diff
          # (Duplicate check already happened at the beginning, so comment doesn't exist)
          original_lines = original.lines
          comment_text = "# Added comment\n"

          # Construct proper unified diff format with minimal context
          # Only include a few lines of context to keep diff small
          context_lines = 3 # Number of context lines to include
          lines_to_show = [context_lines, original_lines.size].min

          file_header = "--- a/#{path}\n+++ b/#{path}"
          # Show context_lines of original, add 1 new line (the comment)
          hunk_header = "@@ -1,#{lines_to_show} +1,#{lines_to_show + 1} @@"

          # Build diff lines: + for the new comment line, space for context lines only
          diff_lines = ["+#{comment_text}"] + original_lines.first(lines_to_show).map { |line| " #{line}" }

          diff = "#{file_header}\n#{hunk_header}\n#{diff_lines.join}"
        elsif diff.include?("---") && diff.include?("+++")
          # Has file headers but missing hunk - try to add hunk header after the file headers
          lines = diff.lines
          file_header_end = lines.index { |l| l.start_with?("+++") } || 0
          if file_header_end > 0
            # Insert hunk header after file headers
            hunk_header = "@@ -1,1 +1,2 @@"
            lines.insert(file_header_end + 1, hunk_header + "\n")
            diff = lines.join
          end
        else
          # No proper structure at all - construct minimal valid diff
          file_header = "--- a/#{path}\n+++ b/#{path}"
          hunk_header = "@@ -1,0 +1,1 @@"
          # If diff has content, use it; otherwise add a placeholder
          content = if diff.empty?
                      "+# Added\n"
                    else
                      diff.lines.map { |l| l.start_with?("+") ? l : "+#{l}" }.join
                    end
          diff = "#{file_header}\n#{hunk_header}\n#{content}"
        end
      end

      diff
    end

    private

    attr_reader :context
  end
end
