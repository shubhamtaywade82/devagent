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
        check("index build") { check_index }
      ]

      connectivity_checks.each do |check_info|
        results << check(check_info[:label]) do
          case check_info[:provider]
          when "openai"
            check_openai(check_info[:role])
          when "ollama"
            check_ollama(check_info[:role])
          else
            "skipped"
          end
        end
      end

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
      "provider: #{context.resolved_provider}, models: #{model_summary}, #{plugin_summary}"
    end

    def check_index
      index = context.index
      index.build!
      index.search("diagnostic", k: 1) # ensure retrieval executes without error
      meta = index.metadata
      "indexed chunks: #{index.document_count}, embedding: #{meta}"
    end

    def check_ollama(role = :default)
      check_ready(role, "Ollama")
    end

    def check_openai(role = :default)
      check_ready(role, "OpenAI")
    end

    def check_repo
      if File.directory?(File.join(context.repo_path, ".git"))
        "git repo detected"
      else
        "⚠ not a git repo, snapshots/commits disabled"
      end
    end

    def model_summary
      {
        default: context.model_for(:default),
        planner: context.model_for(:planner),
        developer: context.model_for(:developer),
        reviewer: context.model_for(:reviewer)
      }.transform_values(&:to_s)
    end

    def plugin_summary
      names = Array(context.plugins).map { |plugin| plugin.name.to_s.split("::").last }.reject(&:empty?)
      names.empty? ? "no plugins detected" : "plugins: #{names.join(", ")}"
    end

    def connectivity_checks
      roles = %i[default planner developer reviewer]
      seen = {}

      roles.filter_map do |role|
        provider = context.provider_for(role)
        next if provider.nil? || seen[provider]

        seen[provider] = true
        label = provider == "openai" ? "openai connectivity" : "ollama connectivity"
        { label: label, provider: provider, role: role }
      end
    end

    def check_ready(role, provider_name)
      response = context.query(
        role: role,
        prompt: "Respond with the single word READY.",
        params: { temperature: 0.0 }
      )
      text = response.to_s.strip
      raise "Unexpected response from #{provider_name}: #{response.inspect}" unless text.downcase.include?("ready")

      "response: #{text}"
    end
  end
end
