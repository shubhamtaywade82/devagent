# frozen_string_literal: true

require "tty/command"

module Devagent
  module UI
    # Command provides enhanced system command execution with live streaming.
    class Command
      Result = Struct.new(:exit_status, :stdout, :stderr, :duration, :command, keyword_init: true) do
        def success?
          exit_status.to_i.zero?
        end

        def failure?
          !success?
        end
      end

      DEFAULT_TIMEOUT = 300

      def initialize(output: $stdout, colorizer: nil)
        @output = output
        @colorizer = colorizer || Colorizer.new
      end

      def run(command, options = {})
        opts = default_options.merge(options.to_h.transform_keys(&:to_sym))
        verbose = opts.delete(:verbose)
        dry_run = opts.delete(:dry_run)
        timeout = opts.delete(:timeout)
        printer = opts.delete(:printer) || default_printer
        cmd = TTY::Command.new(output: output, printer: printer)

        announce(command, verbose)
        return dry_run_result(command) if dry_run

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = cmd.run(*Array(command), **compact_options(opts.merge(timeout: timeout)))
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        build_result(command, result, duration)
      rescue TTY::Command::TimeoutExceeded => e
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        output.puts(colorizer.colorize(:error, "Command timed out: #{command_label(command)}"))
        Result.new(exit_status: 124, stdout: "", stderr: e.message, command: command_label(command),
                   duration: duration)
      rescue TTY::Command::ExitError => e
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        build_result(command, e.result, duration)
      rescue StandardError => e
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        output.puts(colorizer.colorize(:error, "Command failed: #{e.message}"))
        Result.new(exit_status: 1, stdout: "", stderr: e.message, command: command_label(command),
                   duration: duration)
      end

      def run_tests(command = "bundle exec rspec", options = {})
        output.puts(colorizer.colorize(:info, "Running tests: #{command}"))
        result = run(command, options)
        if result.exit_status.zero?
          output.puts(colorizer.colorize(:success, "All tests passed."))
          :ok
        else
          output.puts(colorizer.colorize(:error,
                                         "Tests failed with exit status #{result.exit_status}"))
          :failed
        end
      end

      def run_git(command, options = {})
        run(["git", *Array(command)], options)
      end

      def check_command_available(command)
        result = run(["which", command], printer: :null, verbose: false)
        result.exit_status.zero?
      end

      private

      attr_reader :output, :colorizer

      def default_options
        { timeout: DEFAULT_TIMEOUT, verbose: false, dry_run: false }
      end

      def default_printer
        interactive?(output) ? :pretty : :null
      end

      def dry_run_result(command)
        output.puts(colorizer.colorize(:info, "DRY RUN: #{command_label(command)}"))
        Result.new(exit_status: 0, stdout: "", stderr: "", command: command_label(command), duration: 0.0)
      end

      def build_result(command, result, duration)
        Result.new(
          exit_status: result.exit_status,
          stdout: result.out,
          stderr: result.err,
          duration: duration,
          command: command_label(command)
        )
      end

      def command_label(command)
        Array(command).join(" ")
      end

      def announce(command, verbose)
        return unless verbose

        output.puts(colorizer.colorize(:info, "→ #{command_label(command)}"))
      end

      def interactive?(io)
        io.respond_to?(:tty?) ? io.tty? : true
      end

      def compact_options(options)
        options.each_with_object({}) do |(key, value), acc|
          next if value.nil?

          acc[key] = value
        end
      end
    end
  end
end
