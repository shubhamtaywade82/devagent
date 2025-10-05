# frozen_string_literal: true

require "tty/markdown"
require "tty/cursor"
require "tty/screen"

module Devagent
  module UI
    # MarkdownRenderer provides beautiful streaming markdown output for LLM responses.
    class MarkdownRenderer
      def initialize(output: $stdout, width: nil)
        @output = output
        @width = width || TTY::Screen.width - 4
        @cursor = TTY::Cursor
      end

      def render_stream(buffer)
        return if buffer.empty?

        # Hide cursor, move to beginning of line, render, show cursor
        output.print(cursor.hide)
        output.print(cursor.column(0))
        output.print(cursor.clear_line)
        output.print(render_markdown(buffer))
        output.print(cursor.show)
        output.flush
      rescue StandardError => e
        # Fallback to plain text if markdown rendering fails
        output.print(cursor.show)
        output.print(buffer)
        output.flush
      end

      def render_final(buffer)
        return if buffer.empty?

        output.print(cursor.show)
        output.print(render_markdown(buffer))
        output.puts unless buffer.end_with?("\n")
      end

      def render_static(text)
        render_markdown(text)
      end

      private

      attr_reader :output, :width, :cursor

      def render_markdown(text)
        TTY::Markdown.parse(text, width: width)
      end
    end
  end
end