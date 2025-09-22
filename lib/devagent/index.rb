# frozen_string_literal: true

require "parallel"
require "set"
require_relative "util"

module Devagent
  class Index
    def initialize(repo_path, config)
      @repo = repo_path
      @cfg = config
      @docs = []
    end

    def build!
      globs = Array(@cfg["globs"])
      files = globs.flat_map { |pattern| Dir.glob(File.join(@repo, pattern)) }
                   .uniq
                   .reject { |path| File.directory?(path) }
                   .select { |path| Util.text_file?(path) }

      @docs = Parallel.map(files, in_threads: @cfg["threads"] || 4) do |path|
        text = begin
          File.read(path, encoding: "UTF-8")
        rescue StandardError
          ""
        end

        next if text.empty?

        relative_path = path.sub(@repo.end_with?("/") ? @repo : "#{@repo}/", "")
        { path: relative_path, text: text, tokens: tokenize(text) }
      end.compact
    end

    def document_count
      @docs.size
    end

    def retrieve(query, k: 12)
      query_tokens = tokenize(query)

      scored = @docs.map do |doc|
        overlap = (doc[:tokens] & query_tokens).size
        [overlap, doc]
      end

      scored.sort_by { |score, _| -score }
            .take(k)
            .map { |(_, doc)| format_snippet(doc) }
    end

    private

    def tokenize(source)
      source.downcase.scan(/[a-z0-9_]{2,}/).to_set
    end

    def format_snippet(doc)
      head = doc[:text][0, 1200]
      "#{doc[:path]}:\n#{head}"
    end
  end
end
