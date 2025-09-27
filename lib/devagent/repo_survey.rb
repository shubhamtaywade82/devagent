# frozen_string_literal: true

module Devagent
  # RepoSurvey captures a lightweight summary of the repository structure and key docs.
  class RepoSurvey
    DIRECTORY_DESCRIPTIONS = {
      "app" => "Rails application code",
      "bin" => "utility scripts",
      "config" => "configuration files",
      "db" => "database scripts",
      "exe" => "CLI entrypoints",
      "lib" => "library runtime code",
      "pkg" => "packaged artifacts",
      "sig" => "type signatures",
      "spec" => "RSpec tests",
      "src" => "application source"
    }.freeze

    FILE_DESCRIPTIONS = {
      "Gemfile" => "Ruby dependencies",
      "Rakefile" => "Rake tasks",
      "README.md" => "project overview",
      "CHANGELOG.md" => "release notes",
      "devagent.gemspec" => "gem specification",
      "generate_context.sh" => "context generator script"
    }.freeze

    DOC_CANDIDATES = %w[README.md README.rdoc README.txt CHANGELOG.md CHANGELOG.txt].freeze
    DOC_PREVIEW_LIMIT = 600
    TOP_LEVEL_LIMIT = 10

    attr_reader :repo_path

    def initialize(repo_path)
      @repo_path = repo_path
    end

    def capture!
      @structure_lines = build_structure_lines
      @key_file_lines = build_key_file_lines
      @doc_previews = build_doc_previews
      self
    end

    def structure_lines
      @structure_lines ||= build_structure_lines
    end

    def key_file_lines
      @key_file_lines ||= build_key_file_lines
    end

    def doc_previews
      @doc_previews ||= build_doc_previews
    end

    def summary_text
      sections = []
      sections << "Directories: #{structure_lines.join(", ")}" if structure_lines.any?
      sections << "Key files: #{key_file_lines.join(", ")}" if key_file_lines.any?
      doc_previews.each do |path, preview|
        sections << "#{path}:\n#{preview}"
      end
      sections.join("\n\n")
    end

    private

    def build_structure_lines
      top_level_directories.take(TOP_LEVEL_LIMIT).map do |name|
        label = "#{name}/"
        description = DIRECTORY_DESCRIPTIONS[name]
        description ? "#{label} (#{description})" : label
      end
    end

    def build_key_file_lines
      FILE_DESCRIPTIONS.keys.flat_map do |filename|
        absolute = File.join(repo_path, filename)
        next [] unless File.exist?(absolute)

        description = FILE_DESCRIPTIONS[filename]
        description ? ["#{filename} (#{description})"] : [filename]
      end
    end

    def build_doc_previews
      DOC_CANDIDATES.each_with_object({}) do |candidate, previews|
        absolute = File.join(repo_path, candidate)
        next unless File.file?(absolute)

        snippet = read_preview(absolute)
        previews[candidate] = snippet unless snippet.empty?
      end
    end

    def top_level_directories
      entries = Dir.children(repo_path)
      entries.select do |entry|
        next false if entry.start_with?(".")

        File.directory?(File.join(repo_path, entry))
      end.sort
    rescue Errno::ENOENT
      []
    end

    def read_preview(path)
      content = File.read(path, encoding: "UTF-8")
      preview = content.slice(0, DOC_PREVIEW_LIMIT).to_s
      preview << "\n…" if content.length > DOC_PREVIEW_LIMIT
      preview.strip
    rescue StandardError
      ""
    end
  end
end
