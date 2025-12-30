# frozen_string_literal: true

module Devagent
  module UI
    # Toolkit bundles UI helpers for orchestration and diagnostics.
    class Toolkit
      attr_reader :output, :colorizer

      def initialize(output: $stdout, input: $stdin)
        @output = output
        @input = input
        @colorizer = Colorizer.new(enabled: interactive?)
      end

      def reader(history: nil)
        @reader ||= Reader.new(input: input, output: output, history: history)
      end

      def prompt
        @prompt ||= Prompt.new(output: output, input: input, enabled: interactive?)
      end

      def spinner(message)
        Spinner.new(message, output: output, colorizer: colorizer, enabled: interactive?)
      end

      def table(header:, rows:)
        Table.new(header: header, rows: rows, output: output)
      end

      def markdown_renderer
        @markdown_renderer ||= MarkdownRenderer.new(output: output)
      end

      def logger
        @logger ||= Logger.new(output: output)
      end

      def box
        @box ||= Box.new(output: output, colorizer: colorizer)
      end

      def command
        @command ||= Command.new(output: output, colorizer: colorizer)
      end

      def progress
        @progress ||= Progress.new(output: output, colorizer: colorizer)
      end

      def interactive?
        output.respond_to?(:tty?) ? output.tty? : false
      end

      private

      attr_reader :input
    end
  end
end
