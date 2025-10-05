# frozen_string_literal: true

require "tty/table"

module Devagent
  module UI
    # Table renders diagnostic tables with unicode borders when available.
    class Table
      def initialize(header:, rows:, output: $stdout)
        @header = header
        @rows = rows
        @output = output
      end

      def render
        table = TTY::Table.new(header: header, rows: rows)
        output.puts(table.render(:unicode, alignments: [:left, :left]))
      end

      private

      attr_reader :header, :rows, :output
    end
  end
end
