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

      # Deterministic selection helper for guided flows.
      #
      # choices can be an Array of strings (returned as the selected string).
      def select(message, choices, default: nil)
        choices = Array(choices).map(&:to_s).reject(&:empty?)
        return default.to_s if !enabled? && default
        return choices.first.to_s unless enabled?
        return "" if choices.empty?

        prompt.select(message) do |menu|
          choices.each { |c| menu.choice c, c }
          menu.default default.to_s if default
        end
      end

      def ask(message, default: nil)
        return default.to_s unless enabled?

        prompt.ask(message) do |q|
          q.default default.to_s if default
        end
      end

      private

      attr_reader :prompt, :output

      def enabled?
        @enabled
      end

      def interactive?(io)
        io.respond_to?(:tty?) ? io.tty? : false
      end
    end
  end
end
