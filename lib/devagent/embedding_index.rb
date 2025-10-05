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

    META_FILENAME = "embeddings.meta.json".freeze

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
      ensure_backend_consistency!
    end

    def build!
      chunks = enumerate_chunks
      return [] if chunks.empty?

      embeddings = []
      chunk_texts = chunks.map { |chunk| chunk[:text] }
      vectors = embed_many(chunk_texts)
      return [] if vectors.empty?

      chunks.each_with_index do |chunk, idx|
        vector = vectors[idx]
        next unless valid_vector?(vector)

        embeddings << Entry.new(
          path: chunk[:path],
          chunk_index: chunk[:chunk_index],
          text: chunk[:text],
          embedding: vector
        )
      end

      store.upsert_many(embeddings.map { |entry| serialize(entry) }) unless embeddings.empty?
      persist_meta(current_backend.merge("dim" => Array(vectors.first).size)) if embeddings.any?
      embeddings
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
      store.all.size
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
        chunk_text(content).map.with_index do |chunk_text, chunk_index|
          { path: path, chunk_index: chunk_index, text: chunk_text }
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

    def ensure_backend_consistency!
      saved = load_meta
      return unless saved

      backend = current_backend
      return if saved["provider"] == backend["provider"] && saved["model"] == backend["model"]

      logger.call("Embedding backend changed (#{saved["provider"]}/#{saved["model"]} -> #{backend["provider"]}/#{backend["model"]}). Rebuilding index…")
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
  end

  Index = EmbeddingIndex
end
