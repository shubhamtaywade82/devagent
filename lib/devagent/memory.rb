# frozen_string_literal: true

require "json"

module Devagent
  class Memory
    def initialize(repo_path)
      @path = File.join(repo_path, ".devagent.memory.json")
      @store = load_store
    end

    def get(key)
      @store[key]
    end

    def set(key, value)
      @store[key] = value
      persist!
    end

    def delete(key)
      removed = @store.delete(key)
      persist! if removed
      removed
    end

    def all
      @store.dup
    end

    def persist!
      File.write(@path, JSON.pretty_generate(@store))
    end

    private

    def load_store
      return {} unless File.exist?(@path)

      JSON.parse(File.read(@path))
    rescue JSON::ParserError
      {}
    end
  end
end
