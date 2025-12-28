# frozen_string_literal: true

require "zeitwerk"
begin
  require "dotenv"
  Dotenv.load
rescue LoadError
  # dotenv is optional; ignore if not installed
end
require_relative "devagent/version"

# Devagent is the primary namespace for the autonomous local agent gem.
module Devagent
  class Error < StandardError; end

  def self.loader
    @loader ||= Zeitwerk::Loader.for_gem.tap do |loader|
      loader.ignore("#{__dir__}/devagent/version.rb")
      loader.inflector.inflect("cli" => "CLI")
      loader.setup
    end
  end
end

Devagent.loader
