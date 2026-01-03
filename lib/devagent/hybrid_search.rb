# frozen_string_literal: true

module Devagent
  # HybridSearch combines grep (exact/regex matches) with embedding (semantic) retrieval.
  #
  # Use cases:
  # - When user mentions specific symbols/strings → grep takes priority
  # - When user describes intent vaguely → embeddings take priority
  # - Results are merged and deduplicated
  class HybridSearch
    # Weight for grep results (exact matches are more reliable)
    GREP_WEIGHT = 1.2

    # Weight for embedding results (semantic similarity)
    EMBEDDING_WEIGHT = 1.0

    # Max results from each source
    DEFAULT_LIMIT = 6

    attr_reader :context

    def initialize(context)
      @context = context
    end

    # Search using both grep and embeddings
    #
    # @param query [String] The search query
    # @param patterns [Array<String>] Specific patterns to grep for (optional)
    # @param limit [Integer] Max total results
    # @return [Hash] Combined search results
    def search(query, patterns: nil, limit: DEFAULT_LIMIT)
      patterns ||= extract_patterns(query)

      grep_results = patterns.any? ? grep_search(patterns, limit: limit) : []
      embedding_results = embedding_search(query, limit: limit)

      merged = merge_results(grep_results, embedding_results, limit: limit)

      {
        files: merged.map { |r| r[:path] }.uniq,
        results: merged,
        grep_count: grep_results.size,
        embedding_count: embedding_results.size,
        patterns: patterns
      }
    end

    # Search for exact patterns using grep (via tool_bus or direct)
    def grep_search(patterns, limit: DEFAULT_LIMIT)
      results = []

      patterns.each do |pattern|
        matches = grep_pattern(pattern)
        matches.first(limit).each do |match|
          results << {
            path: match[:path],
            line: match[:line],
            content: match[:content],
            source: :grep,
            score: GREP_WEIGHT,
            pattern: pattern
          }
        end
      end

      results.uniq { |r| [r[:path], r[:line]] }.first(limit)
    end

    # Search using embeddings
    def embedding_search(query, limit: DEFAULT_LIMIT)
      return [] if context.index.document_count.zero?

      snippets = context.index.retrieve(query, limit: limit)
      snippets.map.with_index do |snippet, idx|
        {
          path: snippet["path"],
          chunk_index: snippet["chunk_index"],
          content: snippet["text"],
          source: :embedding,
          # Assign decreasing score based on rank
          score: EMBEDDING_WEIGHT * (1.0 - (idx.to_f / limit))
        }
      end
    end

    private

    # Extract searchable patterns from query
    def extract_patterns(query)
      patterns = []

      # Extract quoted strings
      query.scan(/"([^"]+)"/).each { |m| patterns << m[0] }
      query.scan(/'([^']+)'/).each { |m| patterns << m[0] }

      # Extract CamelCase class/module names
      query.scan(/\b([A-Z][a-zA-Z0-9]+(?:(?:::)?[A-Z][a-zA-Z0-9]+)*)\b/).each { |m| patterns << m[0] }

      # Extract snake_case method/variable names that look significant
      query.scan(/\b([a-z][a-z0-9_]{3,})\b/).each do |m|
        name = m[0]
        # Skip common words
        next if common_word?(name)

        patterns << name
      end

      # Extract file paths
      query.scan(/\b([a-zA-Z0-9_\-\/]+\.[a-z]{1,4})\b/).each { |m| patterns << m[0] }

      patterns.uniq
    end

    def common_word?(word)
      common = %w[this that what where when with from into have been does
                  should would could file code class method function
                  test spec create update delete read write]
      common.include?(word.downcase)
    end

    def grep_pattern(pattern)
      results = []

      begin
        # Use find + grep for basic search
        # Escape pattern for use in regex
        escaped = Regexp.escape(pattern)

        # Search in allowed directories
        globs = Array(context.config.dig("index", "globs") || ["**/*.rb"])
        globs.each do |glob|
          Dir.glob(File.join(context.repo_path, glob)).each do |file|
            next unless File.file?(file) && Util.text_file?(file)

            File.readlines(file, encoding: "UTF-8").each_with_index do |line, idx|
              next unless line.match?(/#{escaped}/i)

              results << {
                path: Pathname.new(file).relative_path_from(Pathname.new(context.repo_path)).to_s,
                line: idx + 1,
                content: line.strip
              }
            end
          rescue StandardError
            # Skip files we can't read
            next
          end
        end
      rescue StandardError => e
        context.tracer&.event("grep_search_failed", message: e.message)
      end

      results
    end

    # Merge grep and embedding results, with deduplication and scoring
    def merge_results(grep_results, embedding_results, limit:)
      # Build a map of path -> best result
      results_map = {}

      # Add grep results first (higher priority)
      grep_results.each do |result|
        key = result[:path]
        if results_map[key].nil? || results_map[key][:score] < result[:score]
          results_map[key] = result
        end
      end

      # Add embedding results, boosting score if also in grep results
      embedding_results.each do |result|
        key = result[:path]
        if results_map[key]
          # File was also found by grep - boost its score
          results_map[key][:score] += result[:score] * 0.5
          results_map[key][:sources] = [:grep, :embedding]
        else
          results_map[key] = result
          results_map[key][:sources] = [:embedding]
        end
      end

      # Sort by score descending and limit
      results_map.values
                 .sort_by { |r| -r[:score] }
                 .first(limit)
    end
  end
end
