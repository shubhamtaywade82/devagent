# frozen_string_literal: true

require "fileutils"
require "json"

module Devagent
  # VectorStoreSqlite persists embeddings and associated metadata in a SQLite file.
  # The implementation intentionally keeps the math in Ruby so the agent runs even
  # when SQLite extensions (vss0) are unavailable. When the sqlite3 gem cannot be
  # loaded we transparently fall back to an in-memory store.
  class VectorStoreSqlite
    Entry = Struct.new(:key, :embedding, :metadata, keyword_init: true)

    attr_reader :path

    def initialize(path)
      @path = path
      @entries = []
      @db = connect(path)
      load_entries!
    end

    def upsert_many(items)
      Array(items).each do |item|
        embedding = item.fetch(:embedding)
        next unless embedding.is_a?(Array)

        entry = Entry.new(
          key: item.fetch(:key),
          embedding: embedding,
          metadata: item.fetch(:metadata)
        )
        upsert_entry(entry)
      end
      persist_entries!
    end

    def clear!
      @entries.clear
      persist_entries!
    end

    def all
      @entries.dup
    end

    def similar(embedding, limit: 8)
      scored = @entries.map do |entry|
        [cosine_similarity(embedding, entry.embedding), entry]
      end
      scored.sort_by { |(score, _)| -score }.first(limit).map(&:last)
    end

    private

    def connect(path)
      require "sqlite3"
      FileUtils.mkdir_p(File.dirname(path))
      SQLite3::Database.new(path).tap do |db|
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS embeddings (
            key TEXT PRIMARY KEY,
            embedding TEXT NOT NULL,
            metadata TEXT NOT NULL
          );
        SQL
      end
    rescue LoadError, SQLite3::Exception
      nil
    end

    def load_entries!
      if @db
        rows = @db.execute("SELECT key, embedding, metadata FROM embeddings")
        @entries = rows.map do |key, embedding_json, metadata_json|
          Entry.new(
            key: key,
            embedding: JSON.parse(embedding_json),
            metadata: JSON.parse(metadata_json)
          )
        end
      end
    end

    def upsert_entry(entry)
      existing_index = @entries.index { |e| e.key == entry.key }
      if existing_index
        @entries[existing_index] = entry
      else
        @entries << entry
      end
    end

    def persist_entries!
      return unless @db

      @db.transaction do
        @db.execute("DELETE FROM embeddings")
        @entries.each do |entry|
          @db.execute(
            "INSERT OR REPLACE INTO embeddings (key, embedding, metadata) VALUES (?, ?, ?)",
            [
              entry.key,
              JSON.generate(entry.embedding),
              JSON.generate(entry.metadata)
            ]
          )
        end
      end
    end

    def cosine_similarity(a, b)
      return 0.0 if a.nil? || b.nil? || a.empty? || b.empty?

      dot = a.zip(b).sum { |(x, y)| x.to_f * y.to_f }
      norm_a = Math.sqrt(a.sum { |x| x.to_f**2 })
      norm_b = Math.sqrt(b.sum { |x| x.to_f**2 })
      return 0.0 if norm_a.zero? || norm_b.zero?

      dot / (norm_a * norm_b)
    end
  end
end
