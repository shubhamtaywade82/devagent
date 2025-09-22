# frozen_string_literal: true

require "parallel"
require "set" # rubocop:disable Lint/RedundantRequireStatement -- to_set needs explicit require
require_relative "util"

module Devagent
  # Index builds a lightweight word-token index across repository files.
  class Index
    def initialize(repo_path, config)
      @repo = repo_path
      @cfg = config
      @docs = []
    end

    def build!
      @docs = Parallel.map(target_files, in_threads: threads) do |path|
        text = read_text(path)
        next if text.empty?

        relative_path = relative_path_for(path)
        { path: relative_path, text: text, tokens: tokenize(text) }
      end.compact
    end

    def document_count
      @docs.size
    end

    def retrieve(query, limit: 12)
      query_tokens = tokenize(query)

      scored = @docs.map do |doc|
        overlap = (doc[:tokens] & query_tokens).size
        [overlap, doc]
      end

      scored.sort_by { |score, _| -score }
            .take(limit)
            .map { |(_, doc)| format_snippet(doc) }
    end

    private

    def threads
      @cfg["threads"] || 4
    end

    def target_files
      Array(@cfg["globs"])
        .flat_map { |pattern| Dir.glob(File.join(@repo, pattern)) }
        .uniq
        .reject { |path| File.directory?(path) }
        .select { |path| Util.text_file?(path) }
    end

    def read_text(path)
      File.read(path, encoding: "UTF-8")
    rescue StandardError
      ""
    end

    def relative_path_for(path)
      prefix = @repo.end_with?("/") ? @repo : "#{@repo}/"
      path.sub(prefix, "")
    end

    def tokenize(source)
      source.downcase.scan(/[a-z0-9_]{2,}/).to_set
    end

    def format_snippet(doc)
      head = doc[:text][0, 1200]
      "#{doc[:path]}:\n#{head}"
    end
  end
end
