# frozen_string_literal: true

begin
  require "readline"
  READLINE_AVAILABLE = true
rescue LoadError
  READLINE_AVAILABLE = false
end

module Devagent
  module UI
    # Reader provides REPL-friendly input with history support using Readline.
    class Reader
      def initialize(input: $stdin, output: $stdout, history: nil)
        @output = output
        @input = input
        @history = history
        @last_interrupt_at = nil
        setup_readline if READLINE_AVAILABLE
      end

      def read_line(prompt)
        if READLINE_AVAILABLE && @input.tty?
          # Don't let Readline auto-add to history (pass false)
          # We'll manage it manually to ensure deduplication
          line = Readline.readline(prompt, false)
          return nil if line.nil?

          line = line.strip
          return "" if line.empty?

          # Add to persistent history (handles deduplication)
          history&.add(line)
          # Update Readline history from persistent storage
          update_history
          line
        else
          output.print(prompt)
          @input.gets&.chomp
        end
      rescue Interrupt
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if @last_interrupt_at && (now - @last_interrupt_at) <= 2.0
          # Let the caller handle exit on second interrupt
          raise
        end
        @last_interrupt_at = now
        output.puts
        output.puts("Interrupted. Press Ctrl+C again to exit.")
        retry
      end

      def update_history
        return unless READLINE_AVAILABLE && history

        # Load history from persistent storage into Readline
        Readline::HISTORY.clear
        history.entries.each do |entry|
          Readline::HISTORY.push(entry) unless entry.strip.empty?
        end
      end

      private

      attr_reader :output, :history

      def setup_readline
        return unless history

        # Configure Readline
        Readline.completion_append_character = nil
        Readline.completion_proc = nil

        # Load initial history
        update_history
      end
    end
  end
end
