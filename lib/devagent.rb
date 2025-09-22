# frozen_string_literal: true

require "zeitwerk"
require_relative "devagent/version"

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
