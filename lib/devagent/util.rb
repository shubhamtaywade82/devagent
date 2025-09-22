# frozen_string_literal: true

require "open3"

module Devagent
  module Util
    module_function

    def run!(cmd, chdir:)
      stdout, stderr, status = Open3.capture3(cmd, chdir: chdir)
      raise "Command failed (#{cmd}): #{stderr}" unless status.success?

      stdout
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
