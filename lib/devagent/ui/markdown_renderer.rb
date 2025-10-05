# frozen_string_literal: true

require "tty/markdown"
require "tty/cursor"

module Devagent
  module UI
    # MarkdownRenderer renders streaming markdown output while respecting TTYs.
    class MarkdownRenderer
      DEFAULT_WIDTH = 100

      def initialize(output: $stdout, width: nil)
        @output = output
        @width = width || detect_width
        @enabled = output.respond_to?(:tty?) ? output.tty? : true
        @markdown = TTY::Markdown
        @cursor = TTY::Cursor
        @buffer = +""
        @streaming = false
      end

      def start
        return unless enabled?

        output.print(cursor.save)
        output.print(cursor.hide)
        @streaming = true
      end

      def append(token)
        if enabled?
          buffer << token
          render
        else
          output.print(token)
        end
      end

      def finish
        if enabled?
          render
          output.print("\n") unless buffer.end_with?("\n")
          output.print(cursor.show)
          output.print("\n")
        else
          output.puts unless buffer.end_with?("\n")
        end
      ensure
        reset!
      end

      private

      attr_reader :output, :width, :markdown, :cursor, :buffer

      def enabled?
        @enabled
      end

      def render
        formatted = markdown.parse(buffer, width: width)
        output.print(cursor.restore)
        output.print(cursor.clear_screen_down)
        output.print(formatted)
      end

      def detect_width
        (ENV["COLUMNS"].to_i.positive? ? ENV["COLUMNS"].to_i : DEFAULT_WIDTH) - 2
      end

      def reset!
        buffer.clear
        @streaming = false
      end
    end
  end
end
