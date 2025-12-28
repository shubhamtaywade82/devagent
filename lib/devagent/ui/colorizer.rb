# frozen_string_literal: true

require "pastel"
require "tty/color"

module Devagent
  module UI
    # Colorizer centralises colour usage across the CLI using Pastel/TTY::Color.
    class Colorizer
      LEVEL_COLORS = {
        info: :cyan,
        warn: :yellow,
        error: :red,
        success: :green,
        prompt: :magenta
      }.freeze

      def initialize(enabled: default_enabled?)
        @pastel = Pastel.new(enabled: enabled)
      end

      def colorize(level, text)
        color = LEVEL_COLORS.fetch(level.to_sym, :white)
        pastel.public_send(color, text)
      end

      def emphasize(text)
        pastel.bold(text)
      end

      def plain(text)
        text
      end

      def enabled?
        pastel.enabled?
      end

      private

      attr_reader :pastel

      def default_enabled?
        TTY::Color.color?
      rescue StandardError
        true
      end
    end
  end
end
