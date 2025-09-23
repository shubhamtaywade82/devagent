# frozen_string_literal: true

require "open3"

module Devagent
  module Util
    module_function

    def run!(cmd, chdir: Dir.pwd)
      stdout, stderr, status = Open3.capture3(cmd, chdir: chdir)
      raise "Command failed (#{cmd}):\nSTDOUT: #{stdout}\nSTDERR: #{stderr}" unless status.success?
      stdout
    end
  end
end
