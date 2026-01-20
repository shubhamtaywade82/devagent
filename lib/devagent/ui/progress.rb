# frozen_string_literal: true

require "tty/progressbar"

module Devagent
  module UI
    # Progress provides progress bars for long-running operations.
    class Progress
      def initialize(output: $stdout, colorizer: nil)
        @output = output
        @colorizer = colorizer || Colorizer.new
      end

      def create_bar(title, total: 100, format: nil)
        format ||= "#{title} [:bar] :percent :current/:total"

        TTY::ProgressBar.new(format, output: output, total: total)
      end

      def embedding_index(total_files)
        create_bar("Building embedding index", total: total_files,
                                               format: "Indexing [:bar] :percent :current/:total files")
      end

      def test_execution(total_tests)
        create_bar("Running tests", total: total_tests,
                                    format: "Testing [:bar] :percent :current/:total tests")
      end

      def file_processing(total_files)
        create_bar("Processing files", total: total_files,
                                       format: "Processing [:bar] :percent :current/:total files")
      end

      def multi_bar(titles_and_totals)
        bars = titles_and_totals.map do |title, total|
          create_bar(title, total: total)
        end

        MultiBar.new(bars)
      end

      # Helper class for managing multiple progress bars
      class MultiBar
        def initialize(bars)
          @bars = bars
          @current_bar = 0
        end

        def advance(amount = 1)
          bars[current_bar].advance(amount)
        end

        def next_bar!
          bars[current_bar]&.finish
          @current_bar += 1
          bars[current_bar]&.start
        end

        def finish_all!
          bars.each(&:finish)
        end

        private

        attr_reader :bars, :current_bar
      end

      private

      attr_reader :output, :colorizer
    end
  end
end
