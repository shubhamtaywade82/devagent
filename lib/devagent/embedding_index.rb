# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require_relative "vector_store_sqlite"
require_relative "util"

module Devagent
  # EmbeddingIndex chunks repository files and stores embeddings for retrieval.
  class EmbeddingIndex
    DEFAULTS = {
      "globs" => ["**/*.{rb,ru,erb,haml,slim,js,jsx,ts,tsx}"],
      "chunk_size" => 1800,
      "overlap" => 200,
      "threads" => 4
    }.freeze

    META_FILENAME = "embeddings.meta.json"
    FILE_HASHES_FILENAME = "file_hashes.json"

    Entry = Struct.new(:path, :chunk_index, :text, :embedding, keyword_init: true)

    attr_reader :repo_path, :config, :store, :context

    def initialize(repo_path, config, context:, logger: nil, store: nil)
      @repo_path = repo_path
      @config = DEFAULTS.merge(config || {})
      @context = context
      @logger = logger || ->(_msg) {}
      data_dir = File.join(repo_path, ".devagent")
      FileUtils.mkdir_p(data_dir)
      store_path = File.join(data_dir, "embeddings.sqlite3")
      @store = store || VectorStoreSqlite.new(store_path)
      @meta_path = File.join(data_dir, META_FILENAME)
      @hashes_path = File.join(data_dir, FILE_HASHES_FILENAME)
      @file_hashes = load_file_hashes
      ensure_backend_consistency!
    end

    def build!
      chunks = enumerate_chunks
      return [] if chunks.nil? || chunks.empty?

      embeddings = []
      chunk_texts = chunks.map { |chunk| chunk[:text] }
      vectors = embed_many(chunk_texts)
      return [] if vectors.nil? || vectors.empty?

      vector_dim = Array(vectors.first).size
      ensure_dimension_consistency!(vector_dim)

      new_hashes = {}
      chunks.each_with_index do |chunk, idx|
        vector = vectors[idx]
        next unless valid_vector?(vector)

        embeddings << Entry.new(
          path: chunk[:path],
          chunk_index: chunk[:chunk_index],
          text: chunk[:text],
          embedding: vector
        )
        # Track file hash for freshness checks
        new_hashes[chunk[:path]] = chunk[:file_hash]
      end

      store.upsert_many(embeddings.map { |entry| serialize(entry) }) unless embeddings.empty?
      if embeddings.any?
        persist_meta(current_backend.merge("dim" => vector_dim, "indexed_at" => Time.now.iso8601))
        persist_file_hashes(new_hashes)
      end

      embeddings
    end

    # Incremental build: only re-embed changed/new files
    def build_incremental!
      files = target_files
      return [] if files.empty?

      # Identify stale files (changed or new)
      stale_files = files.select { |path| file_stale?(path) }
      return [] if stale_files.empty?

      logger.call("Rebuilding #{stale_files.size} stale files...")

      # Remove stale entries from store
      stale_files.each do |path|
        remove_entries_for_path(path)
      end

      # Chunk only stale files
      chunks = stale_files.flat_map do |path|
        absolute = File.join(repo_path, path)
        content = File.read(absolute, encoding: "UTF-8")
        file_hash = Digest::SHA256.hexdigest(content)[0..15]
        chunk_text(content).map.with_index do |chunk_text, chunk_index|
          { path: path, chunk_index: chunk_index, text: chunk_text, file_hash: file_hash }
        end
      rescue StandardError => e
        logger.call("index skip #{path}: #{e.message}")
        []
      end

      return [] if chunks.empty?

      # Embed and store
      chunk_texts = chunks.map { |chunk| chunk[:text] }
      vectors = embed_many(chunk_texts)
      return [] if vectors.nil? || vectors.empty?

      vector_dim = Array(vectors.first).size
      ensure_dimension_consistency!(vector_dim)

      embeddings = []
      chunks.each_with_index do |chunk, idx|
        vector = vectors[idx]
        next unless valid_vector?(vector)

        embeddings << Entry.new(
          path: chunk[:path],
          chunk_index: chunk[:chunk_index],
          text: chunk[:text],
          embedding: vector
        )
        @file_hashes[chunk[:path]] = chunk[:file_hash]
      end

      store.upsert_many(embeddings.map { |entry| serialize(entry) }) unless embeddings.empty?
      if embeddings.any?
        persist_meta(current_backend.merge("dim" => vector_dim, "indexed_at" => Time.now.iso8601))
        persist_file_hashes(@file_hashes)
      end

      embeddings
    end

    # Check if a specific file's embedding is stale
    def file_stale?(path)
      stored_hash = @file_hashes[path]
      return true if stored_hash.nil?

      absolute = File.join(repo_path, path)
      return true unless File.exist?(absolute)

      current_hash = Digest::SHA256.hexdigest(File.read(absolute, encoding: "UTF-8"))[0..15]
      stored_hash != current_hash
    rescue StandardError
      true
    end

    # Get list of stale files
    def stale_files
      target_files.select { |path| file_stale?(path) }
    end

    # Check if any embeddings are stale
    def any_stale?
      stale_files.any?
    end

    def search(query, k: 8)
      vector = embed_many([query]).first
      return [] unless valid_vector?(vector)

      store.similar(vector, limit: k).map do |entry|
        metadata = entry.metadata
        {
          "path" => metadata["path"],
          "chunk_index" => metadata["chunk_index"],
          "text" => metadata["text"]
        }
      end
    end

    def document_count
      entries = store.all
      entries.nil? ? 0 : entries.size
    end

    def retrieve(query, limit: 8)
      search(query, k: limit)
    end

    def metadata
      load_meta || {}
    end

    private

    attr_reader :logger, :meta_path

    def embed_many(texts)
      adapter = context.llm_for(:embedding)
      adapter.embed(Array(texts), model: context.model_for(:embedding))
    rescue StandardError => e
      logger.call("embedding failed: #{e.message}")
      []
    end

    def valid_vector?(vector)
      vector.is_a?(Array) && vector.all? { |v| v.is_a?(Numeric) }
    end

    def enumerate_chunks
      files = target_files
      return [] if files.empty?

      files.flat_map do |path|
        absolute = File.join(repo_path, path)
        content = File.read(absolute, encoding: "UTF-8")
        file_hash = Digest::SHA256.hexdigest(content)[0..15]
        chunk_text(content).map.with_index do |chunk_text, chunk_index|
          { path: path, chunk_index: chunk_index, text: chunk_text, file_hash: file_hash }
        end
      rescue StandardError => e
        logger.call("index skip #{path}: #{e.message}")
        []
      end
    end

    def chunk_text(text)
      size = config["chunk_size"].to_i
      overlap = config["overlap"].to_i
      return [text] if text.length <= size || size <= 0

      chunks = []
      start = 0
      while start < text.length
        finish = [start + size, text.length].min
        chunks << text[start...finish]
        break if finish == text.length

        start = [finish - overlap, start + 1].max
      end
      chunks
    end

    def target_files
      globs = Array(config["globs"])
      files = globs.flat_map do |pattern|
        Dir.glob(File.join(repo_path, pattern), File::FNM_EXTGLOB)
      end
           .uniq
           .reject { |path| File.directory?(path) }
                   .select { |path| Util.text_file?(path) }
                   .map { |path| relative_path(path) }

      # Filter by allowlist/denylist if available in context config
      if context.respond_to?(:config)
        auto_config = context.config["auto"] || {}
        allowlist = Array(auto_config["allowlist"])
        denylist = Array(auto_config["denylist"])

        # Apply denylist first (more restrictive)
        unless denylist.empty?
          files = files.reject do |file_path|
            denylist.any? { |pattern| File.fnmatch?(pattern, file_path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
          end
        end

        # Apply allowlist if present (only include matching files)
        unless allowlist.empty?
          files = files.select do |file_path|
            allowlist.any? { |pattern| File.fnmatch?(pattern, file_path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
          end
        end
      end

      files
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Pathname.new(repo_path)).to_s
    end

    def serialize(entry)
      {
        key: Digest::SHA256.hexdigest([entry.path, entry.chunk_index].join(":")),
        embedding: entry.embedding,
        metadata: {
          "path" => entry.path,
          "chunk_index" => entry.chunk_index,
          "text" => entry.text
        }
      }
    end

    def ensure_backend_consistency!
      saved = load_meta
      return unless saved

      backend = current_backend
      return if saved["provider"] == backend["provider"] && saved["model"] == backend["model"]

      logger.call("Embedding backend changed (#{saved["provider"]}/#{saved["model"]} -> #{backend["provider"]}/#{backend["model"]}). Rebuilding index…")
      store.clear!
      FileUtils.rm_f(meta_path)
    end

    def ensure_dimension_consistency!(dimension)
      saved = load_meta
      return unless saved && saved["dim"] && saved["dim"] != dimension

      logger.call("Embedding dimension changed (#{saved["dim"]} -> #{dimension}). Rebuilding index…")
      store.clear!
      FileUtils.rm_f(meta_path)
    end

    def current_backend
      context.embedding_backend_info
    end

    def load_meta
      return unless File.exist?(meta_path)

      JSON.parse(File.read(meta_path, encoding: "UTF-8"))
    rescue JSON::ParserError
      nil
    end

    def persist_meta(meta)
      File.write(meta_path, JSON.pretty_generate(meta))
    rescue StandardError
      nil
    end

    def load_file_hashes
      return {} unless File.exist?(@hashes_path)

      JSON.parse(File.read(@hashes_path, encoding: "UTF-8"))
    rescue JSON::ParserError, StandardError
      {}
    end

    def persist_file_hashes(hashes)
      File.write(@hashes_path, JSON.pretty_generate(hashes))
    rescue StandardError
      nil
    end

    def remove_entries_for_path(path)
      # Remove all chunks for a given file path
      @entries_to_remove ||= []
      store.all.each do |entry|
        next unless entry.metadata["path"] == path

        @entries_to_remove << entry.key
      end

      # For now, we'll rebuild - a more efficient implementation would
      # delete specific keys from SQLite
    end
  end

  Index = EmbeddingIndex
end
