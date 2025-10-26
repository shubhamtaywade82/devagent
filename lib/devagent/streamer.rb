# frozen_string_literal: true

module Devagent
  # Streamer streams LLM output to the console and session memory.
  class Streamer
    def initialize(context, output: $stdout, ui: nil)
      @context = context
      @ui = ui
      @output = ui ? ui.output : output
      @markdown_renderer = ui&.respond_to?(:markdown_renderer) ? ui.markdown_renderer : nil
      @colorizer = ui&.respond_to?(:colorizer) ? ui.colorizer : nil
    end

    def say(message, level: :info, markdown: false)
      text = message.to_s
      return if quiet? && text.strip.empty?

      rendered = if markdown && markdown_renderer
                   markdown_renderer.render_static(text)
                 else
                   colorize(level, text)
                 end

      output.puts(rendered)
      context.tracer.event("log", message: message, level: level)
      context.session_memory.append("assistant", message)
    end

    def with_stream(role, markdown: true, silent: false)
      buffer = +""
      use_markdown = !silent && markdown && markdown_renderer
      handler = proc do |chunk|
        chunk_str = chunk.to_s
        buffer << chunk_str
        record_token(role, chunk_str)
        next if silent

        if use_markdown
          markdown_renderer.render_stream(buffer)
        else
          token(role, chunk_str)
        end
      end
      result = yield handler
      final = result.nil? || result.to_s.empty? ? buffer : result.to_s
      unless silent
        if use_markdown
          markdown_renderer.render_final(final)
        else
          output.puts unless final.end_with?("\n")
        end
      end
      context.tracer.event("log", message: final, level: :info)
      context.session_memory.append("assistant", final)
      final
    end

    def token(role, text)
      emit_chunk(text)
      record_token(role, text)
    end

    private

    attr_reader :context, :output, :ui, :markdown_renderer, :colorizer

    def quiet?
      return false unless context.respond_to?(:config)

      context.config.dig("ui", "quiet") == true
    end

    def colorize(level, message)
      return message unless colorizer

      colorizer.colorize(level, message)
    end

    def emit_chunk(text)
      output.print(text)
      output.flush
    end

    def record_token(role, text)
      context.tracer.event("stream", role: role, token: text)
    end
  end
end
