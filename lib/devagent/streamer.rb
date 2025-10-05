# frozen_string_literal: true

module Devagent
  # Streamer streams LLM output to the console and session memory.
  class Streamer
    def initialize(context, output: $stdout)
      @context = context
      @output = output
    end

    def say(message)
      output.puts(message)
      context.tracer.event("log", message: message)
      context.session_memory.append("assistant", message)
    end

    def token(role, text)
      output.print(text)
      output.flush
      context.tracer.event("stream", role: role, token: text)
    end

    private

    attr_reader :context, :output
  end
end
