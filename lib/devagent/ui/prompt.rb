# frozen_string_literal: true

require "tty/prompt"

module Devagent
  module UI
    # Prompt provides confirmation helpers that gracefully degrade when not interactive.
    class Prompt
      def initialize(output: $stdout, input: $stdin, enabled: nil)
        @output = output
        @enabled = enabled.nil? ? interactive?(output) : enabled
        @prompt = TTY::Prompt.new(output: output, input: input, enable_color: false)
      end

      def confirm(message, default: true)
        return default unless enabled?

        prompt.yes?(message) { |q| q.default default }
      end

      private

      attr_reader :prompt, :output

      def enabled?
        @enabled
      end

      def interactive?(io)
        io.respond_to?(:tty?) ? io.tty? : true
      end
    end
  end
end
