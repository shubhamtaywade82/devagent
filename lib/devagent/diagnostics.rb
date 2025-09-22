# frozen_string_literal: true

module Devagent
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
      config = context.config || {}
      model = config["model"].to_s
      raise "LLM model not configured. Set `model` in .devagent.yml." if model.empty?

      plugins = Array(context.plugins).map { |plugin| plugin.name.to_s.split("::").last }.reject(&:empty?)
      plugin_summary = plugins.empty? ? "no plugins detected" : "plugins: #{plugins.join(', ')}"
      "model: #{model}, #{plugin_summary}"
    end

    def check_index
      index = context.index
      index.build!
      index.retrieve("diagnostic", k: 1) # ensure retrieval executes without error
      "indexed files: #{index.document_count}"
    end

    def check_ollama
      response = context.llm.call("Respond with the single word READY.")
      text = response.to_s.strip
      raise "Unexpected response from Ollama: #{response.inspect}" unless text.downcase.include?("ready")

      "response: #{text}"
    end
  end
end
