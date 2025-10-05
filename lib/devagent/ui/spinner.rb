# frozen_string_literal: true

require "tty/spinner"

module Devagent
  module UI
    # Spinner wraps TTY::Spinner with safe defaults for non-interactive outputs.
    class Spinner
      def initialize(message, output: $stdout, colorizer: Colorizer.new(enabled: false), enabled: nil)
        @message = message
        @output = output
        @colorizer = colorizer
        @enabled = enabled.nil? ? interactive?(output) : enabled
        @spinner = build_spinner if enabled?
      end

      def run
        start
        result = yield
        success
        result
      rescue StandardError => e
        failure(e)
        raise
      ensure
        stop
      end

      private

      attr_reader :message, :output, :spinner, :colorizer

      def start
        if enabled?
          spinner.auto_spin
        else
          output.puts("#{message}...")
        end
      end

      def success
        if enabled?
          spinner.success(colorizer.colorize(:success, "done"))
        else
          output.puts(colorizer.colorize(:success, "✔ #{message}"))
        end
      end

      def failure(error)
        if enabled?
          spinner.error(colorizer.colorize(:error, "error"))
        else
          output.puts(colorizer.colorize(:error, "✖ #{message}: #{error.message}"))
        end
      end

      def stop
        spinner&.stop if enabled?
      end

      def build_spinner
        TTY::Spinner.new("[:spinner] #{message} ...", format: :dots, output: output)
      end

      def enabled?
        @enabled
      end

      def interactive?(io)
        io.respond_to?(:tty?) ? io.tty? : true
      end
    end
  end
end
