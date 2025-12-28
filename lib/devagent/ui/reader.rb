# frozen_string_literal: true

require "tty-reader"

module Devagent
  module UI
    # Reader wraps TTY::Reader to provide REPL-friendly behaviour.
    class Reader
      def initialize(input: $stdin, output: $stdout)
        @output = output
        @reader = TTY::Reader.new(input: input, output: output)
      end

      def read_line(prompt)
        reader.read_line(prompt)
      rescue TTY::Reader::InputInterrupt
        output.puts
        output.puts("Interrupted. Type 'exit' to quit or continue typing.")
        retry
      end

      private

      attr_reader :reader, :output
    end
  end
end
