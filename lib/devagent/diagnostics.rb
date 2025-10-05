# frozen_string_literal: true

module Devagent
  # Diagnostics performs lightweight checks to validate configuration and dependencies.
  class Diagnostics
    def initialize(context, output: $stdout)
      @context = context
      @output = output
    end

    def run
      output.puts("Running Devagent diagnostics...")

      results = [
        check("configuration") { check_configuration },
        check("index build") { check_index },
        check("ollama connectivity") { check_ollama }
      ]

      success = results.all?
      output.puts(success ? "All checks passed." : "Some checks failed.")
      success
    end

    private

    attr_reader :context, :output

    def check(label)
      output.print(" - #{label}... ")
      message = yield
      output.puts("OK")
      output.puts("   #{message}") if message.is_a?(String) && !message.empty?
      true
    rescue StandardError => e
      output.puts("FAIL")
      output.puts("   #{e.message}")
      false
    end

    def check_configuration
      model = configured_model
      "model: #{model}, #{plugin_summary}"
    end

    def check_index
      index = context.index
      index.build!
      index.search("diagnostic", k: 1) # ensure retrieval executes without error
      "indexed chunks: #{index.document_count}"
    end

    def check_ollama
      response = context.chat("Respond with the single word READY.")
      text = response.to_s.strip
      raise "Unexpected response from Ollama: #{response.inspect}" unless text.downcase.include?("ready")

      "response: #{text}"
    end

    def check_repo
      if File.directory?(File.join(context.repo_path, ".git"))
        "git repo detected"
      else
        "⚠ not a git repo, snapshots/commits disabled"
      end
    end

    def configured_model
      model = (context.config || {})["model"].to_s
      raise "LLM model not configured. Set `model` in .devagent.yml." if model.empty?

      model
    end

    def plugin_summary
      names = Array(context.plugins).map { |plugin| plugin.name.to_s.split("::").last }.reject(&:empty?)
      names.empty? ? "no plugins detected" : "plugins: #{names.join(", ")}"
    end
  end
end
