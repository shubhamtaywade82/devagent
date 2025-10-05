# frozen_string_literal: true

require "tty/progressbar"

module Devagent
  module UI
    # Progress provides a convenience wrapper over TTY::ProgressBar.
    class Progress
      def initialize(title, total:, output: $stdout)
        @bar = TTY::ProgressBar.new("#{title} [:bar] :percent", total: total, output: output)
      end

      def advance(step = 1)
        bar.advance(step)
      end

      def finish
        bar.finish
      end

      private

      attr_reader :bar
    end
  end
end
