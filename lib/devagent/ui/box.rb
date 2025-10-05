# frozen_string_literal: true

require "tty/box"

module Devagent
  module UI
    # Box provides formatted message boxes for system notifications and summaries.
    class Box
      def initialize(output: $stdout, colorizer: nil)
        @output = output
        @colorizer = colorizer || Colorizer.new
      end

      def info(title, content, width: nil)
        render_box(title, content, :info, width)
      end

      def success(title, content, width: nil)
        render_box(title, content, :success, width)
      end

      def warning(title, content, width: nil)
        render_box(title, content, :warn, width)
      end

      def error(title, content, width: nil)
        render_box(title, content, :error, width)
      end

      def plan_summary(summary, confidence, actions_count)
        content = [
          summary,
          "",
          "Confidence: #{(confidence * 100).round}%",
          "Actions: #{actions_count}"
        ].join("\n")

        render_box("Plan Summary", content, :info)
      end

      def review_notes(notes)
        render_box("Review Notes", notes, :warn)
      end

      private

      attr_reader :output, :colorizer

      def render_box(title, content, level, width = nil)
        width ||= TTY::Screen.width - 4

        # Colorize the title
        colored_title = colorizer.colorize(level, title)

        # Create the box with colored title
        box_content = TTY::Box.frame(
          "#{colored_title}\n\n#{content}",
          width: width
        )

        output.puts(box_content)
      end
    end
  end
end
