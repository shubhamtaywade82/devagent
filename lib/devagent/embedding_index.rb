# frozen_string_literal: true

require "digest"
require "fileutils"
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
      "embed_model" => "nomic-embed-text",
      "threads" => 4
    }.freeze

    Entry = Struct.new(:path, :chunk_index, :text, :embedding, keyword_init: true)

    attr_reader :repo_path, :config, :store

    def initialize(repo_path, config, embedder:, logger: nil, store: nil)
      @repo_path = repo_path
      @config = DEFAULTS.merge(config || {})
      @embedder = embedder
      @logger = logger || ->(_msg) {}
      data_dir = File.join(repo_path, ".devagent")
      FileUtils.mkdir_p(data_dir)
      store_path = File.join(data_dir, "embeddings.sqlite3")
      @store = store || VectorStoreSqlite.new(store_path)
    end

    def build!
      chunks = enumerate_chunks
      return if chunks.empty?

      embeddings = chunks.filter_map do |chunk|
        vector = embed(chunk[:text])
        next unless vector

        Entry.new(
          path: chunk[:path],
          chunk_index: chunk[:chunk_index],
          text: chunk[:text],
          embedding: vector
        )
      end

      store.upsert_many(embeddings.map { |entry| serialize(entry) }) unless embeddings.empty?
      embeddings
    end

    def search(query, k: 8)
      vector = embed(query)
      return [] if vector.nil?

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
      store.all.size
    end

    def retrieve(query, limit: 8)
      search(query, k: limit)
    end

    private

    def embed(text)
      vector = @embedder.call(text, model: config["embed_model"])
      vector if vector.is_a?(Array) && vector.all? { |v| v.is_a?(Numeric) }
    rescue StandardError => e
      @logger.call("embedding failed: #{e.message}")
      nil
    end

    def enumerate_chunks
      files = target_files
      return [] if files.empty?

      files.flat_map do |path|
        absolute = File.join(repo_path, path)
        content = File.read(absolute, encoding: "UTF-8")
        chunk_text(content).map.with_index do |chunk_text, chunk_index|
          { path: path, chunk_index: chunk_index, text: chunk_text }
        end
      rescue StandardError => e
        @logger.call("index skip #{path}: #{e.message}")
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
      globs.flat_map do |pattern|
        Dir.glob(File.join(repo_path, pattern), File::FNM_EXTGLOB)
      end
           .uniq
           .reject { |path| File.directory?(path) }
           .select { |path| Util.text_file?(path) }
           .map { |path| relative_path(path) }
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
  end

  Index = EmbeddingIndex
end
