# frozen_string_literal: true

require "open3"

module Devagent
  # Util contains shared helper routines for shelling out and file checks.
  module Util
    module_function

    def run!(cmd, chdir: Dir.pwd)
      stdout, stderr, status = Open3.capture3(cmd, chdir: chdir)
      raise "Command failed (#{cmd}):\nSTDOUT: #{stdout}\nSTDERR: #{stderr}" unless status.success?

      stdout
    end

    # Run a command and always return output, even if exit code is non-zero
    # Useful for commands like rubocop that return non-zero to indicate issues found
    def run_capture(cmd, chdir: Dir.pwd)
      stdout, stderr, status = Open3.capture3(cmd, chdir: chdir)
      {
        "stdout" => stdout,
        "stderr" => stderr,
        "exit_code" => status.exitstatus,
        "success" => status.success?
      }
    end

    def text_file?(path)
      data = begin
        File.binread(path, 512)
      rescue StandardError
        return false
      end

      (data.count("^ -~\t\r\n").to_f / [data.size, 1].max) < 0.1
    end
  end
end
