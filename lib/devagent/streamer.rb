# frozen_string_literal: true

require_relative "ui"

module Devagent
  # Streamer streams LLM output to the console and session memory.
  class Streamer
    attr_reader :output

    def initialize(context, output: $stdout, ui: UI::Toolkit.new(output: output))
      @context = context
      @output = output
      @ui = ui
      @buffers = Hash.new { |hash, key| hash[key] = +"" }
      @renderers = Hash.new { |hash, key| hash[key] = UI::MarkdownRenderer.new(output: output) }
    end

    def say(message, level: :info)
      rendered = ui.colorizer.colorize(level, message)
      output.puts(rendered)
      context.tracer.event("log", message: message, level: level)
      context.session_memory.append("assistant", message)
    end

    def with_stream(role)
      renderer = renderer_for(role)
      renderer.start
      append = lambda do |token|
        buffers[role] << token
        renderer.append(token)
        context.tracer.event("stream", role: role, token: token)
      end
      result = yield append
      result
    ensure
      renderer&.finish
      finalize(role)
    end

    private

    attr_reader :context, :ui, :buffers, :renderers

    def renderer_for(role)
      renderers[role] ||= UI::MarkdownRenderer.new(output: output)
    end

    def finalize(role)
      content = buffers.delete(role)
      return if content.to_s.empty?

      context.session_memory.append("assistant", content)
    end
  end
end
