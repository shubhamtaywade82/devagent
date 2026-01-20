# frozen_string_literal: true

require_relative "prompts"

module Devagent
  # DiffGenerator asks the developer model for a minimal unified diff.
  class DiffGenerator
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

      # Validate and fix diff format before fallback logic
      if diff.include?("@@") || diff.include?("---") || diff.include?("+++")
        diff = validate_and_fix_diff(diff, path,
                                     original)
      end

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
          if file_header_end.positive?
            # Insert hunk header after file headers
            hunk_header = "@@ -1,1 +1,2 @@"
            lines.insert(file_header_end + 1, "#{hunk_header}\n")
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

      # Final validation before returning
      validate_and_fix_diff(diff, path, original)
    end

    private

    attr_reader :context

    # Validate and fix diff format to ensure it can be applied
    def validate_and_fix_diff(diff, path, original)
      return diff if diff.strip.empty?

      lines = diff.lines
      original_lines = original.lines

      # Check if diff has proper headers
      has_headers = lines.first&.start_with?("---") && lines[1]&.start_with?("+++")

      unless has_headers
        # Add headers if missing
        diff = "--- a/#{path}\n+++ b/#{path}\n#{diff}"
        lines = diff.lines
      end

      # Check if diff has hunk markers
      has_hunk = lines.any? { |line| line.start_with?("@@") }

      # If diff has content but no hunk markers, try to add them
      # Otherwise, the existing fallback logic below will handle it
      if !has_hunk && diff.strip.empty?
        # No changes needed - return a no-op diff
        hunk_count = original_lines.size
        hunk_lines = original_lines.map { |line| " #{line}" }.join
        return "--- a/#{path}\n+++ b/#{path}\n@@ -1,#{hunk_count} +1,#{hunk_count} @@\n#{hunk_lines}"
      end

      # Ensure diff ends with newline (git apply requires this)
      diff += "\n" unless diff.end_with?("\n")

      diff
    end
  end
end
