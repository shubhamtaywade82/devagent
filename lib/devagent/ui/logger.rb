# frozen_string_literal: true

require "tty/logger"

module Devagent
  module UI
    # Logger wraps TTY::Logger with sane defaults and shared formatting.
    class Logger
      LEVELS = %i[debug info warn error success].freeze

      def initialize(output: $stdout, level: :info)
        @logger = TTY::Logger.new do |config|
          config.level = level
          config.output = output
        end
      end

      LEVELS.each do |level|
        define_method(level) do |message|
          logger.public_send(level, message)
        end
      end

      private

      attr_reader :logger
    end
  end
end
