# frozen_string_literal: true

module Devagent
  # RetrievalController enforces embedding-based retrieval constraints.
  #
  # Controller invariants:
  # 1. If repo_empty → skip embeddings entirely
  # 2. If intent is vague → embeddings query is mandatory
  # 3. fs.read must target retrieved_files (unless explicit path given)
  # 4. Retrieval happens once per goal, cached in state
  #
  # This class bridges the gap between embedding infrastructure and planning.
  class RetrievalController
    # Minimum document count to consider embeddings useful
    MIN_DOCUMENTS_FOR_RETRIEVAL = 1

    # Default retrieval limit
    DEFAULT_RETRIEVAL_LIMIT = 8

    # Intents that require mandatory retrieval
    VAGUE_INTENTS = %w[CODE_EDIT DEBUG CODE_REVIEW].freeze

    # Intents that skip retrieval entirely
    SKIP_RETRIEVAL_INTENTS = %w[EXPLANATION GENERAL REJECT].freeze

    attr_reader :context, :cache

    def initialize(context)
      @context = context
      @cache = {}
    end

    # Check if repo is empty (no indexed documents)
    def repo_empty?
      document_count.zero?
    end

    # Get document count from embedding index
    def document_count
      @document_count ||= context.index.document_count
    rescue StandardError
      0
    end

    # Check if embeddings are ready for use
    def embeddings_ready?
      !repo_empty? && context.index.metadata.any?
    end

    # Check if embeddings are stale (provider/model changed)
    def embeddings_stale?
      meta = context.index.metadata
      return true if meta.nil? || meta.empty?

      current = context.embedding_backend_info
      meta["provider"] != current["provider"] || meta["model"] != current["model"]
    end

    # Retrieve files for a goal, with caching
    #
    # @param goal [String] The user's goal/task
    # @param intent [String] The classified intent
    # @param limit [Integer] Max number of results
    # @return [Hash] Retrieval result with :files, :skip_reason, :cached
    def retrieve_for_goal(goal, intent:, limit: DEFAULT_RETRIEVAL_LIMIT)
      cache_key = goal_cache_key(goal)

      # Return cached result if available
      if cache[cache_key]
        cached = cache[cache_key].dup
        cached[:cached] = true
        return cached
      end

      result = perform_retrieval(goal, intent: intent, limit: limit)
      cache[cache_key] = result
      result
    end

    # Get retrieved files for path validation
    #
    # @param goal [String] The user's goal/task
    # @return [Array<String>] List of retrieved file paths
    def retrieved_files_for(goal)
      cache_key = goal_cache_key(goal)
      return [] unless cache[cache_key]

      cache[cache_key][:files] || []
    end

    # Validate that a path is in the retrieved files (or explicitly specified)
    #
    # @param path [String] The file path to validate
    # @param goal [String] The user's goal/task
    # @param explicit_paths [Array<String>] Paths explicitly mentioned by user
    # @return [Boolean] Whether the path is valid
    def path_in_retrieved?(path, goal:, explicit_paths: [])
      return true if explicit_paths.include?(path)

      retrieved = retrieved_files_for(goal)
      return true if retrieved.empty? # No retrieval constraint

      retrieved.include?(path)
    end

    # Get index status for diagnostics
    def index_status
      {
        document_count: document_count,
        repo_empty: repo_empty?,
        embeddings_ready: embeddings_ready?,
        embeddings_stale: embeddings_stale?,
        metadata: context.index.metadata,
        backend: context.embedding_backend_info
      }
    end

    # Clear the retrieval cache
    def clear_cache!
      @cache = {}
      @document_count = nil
    end

    private

    def perform_retrieval(goal, intent:, limit:)
      # Rule 1: If repo is empty, skip embeddings entirely
      if repo_empty?
        return {
          files: [],
          snippets: [],
          skip_reason: :repo_empty,
          cached: false
        }
      end

      # Rule 2: Determine if retrieval is mandatory
      mandatory = VAGUE_INTENTS.include?(intent.to_s.upcase)
      skip = SKIP_RETRIEVAL_INTENTS.include?(intent.to_s.upcase)

      if skip && !mandatory
        return {
          files: [],
          snippets: [],
          skip_reason: :intent_skipped,
          cached: false
        }
      end

      # Rule 3: Check if embeddings are stale
      if embeddings_stale?
        context.tracer&.event("retrieval_skipped", reason: "embeddings_stale")
        return {
          files: [],
          snippets: [],
          skip_reason: :embeddings_stale,
          cached: false
        }
      end

      # Perform the actual retrieval
      snippets = context.index.retrieve(goal, limit: limit)
      files = snippets.map { |s| s["path"] }.uniq

      context.tracer&.event("retrieval_completed",
                            files_count: files.size,
                            snippets_count: snippets.size,
                            mandatory: mandatory)

      {
        files: files,
        snippets: snippets,
        skip_reason: nil,
        cached: false
      }
    rescue StandardError => e
      context.tracer&.event("retrieval_failed", message: e.message)
      {
        files: [],
        snippets: [],
        skip_reason: :retrieval_error,
        error: e.message,
        cached: false
      }
    end

    def goal_cache_key(goal)
      require "digest"
      Digest::SHA256.hexdigest(goal.to_s.strip.downcase)[0..15]
    end
  end
end
