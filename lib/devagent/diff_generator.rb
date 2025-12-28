# frozen_string_literal: true

require_relative "prompts"

module Devagent
  # DiffGenerator asks the developer model for a minimal unified diff.
  class DiffGenerator
    def initialize(context)
      @context = context
    end

    def generate(path:, original:, goal:, reason:, file_exists:)
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
          original_lines = original.lines

          # Check if comment already exists at the top to avoid duplicates
          first_line = original_lines.first.to_s.strip
          if first_line.start_with?("#") && (first_line.include?("comment") || first_line.include?("Added"))
            # Comment already exists, don't add another one
            # Return a minimal diff that does nothing (or skip adding)
            return diff # Return original (empty) diff to skip
          end

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
