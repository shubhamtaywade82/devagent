# frozen_string_literal: true

require "stringio"

RSpec.describe Devagent::Streamer do
  let(:output) { StringIO.new }
  let(:session_memory) { instance_double(Devagent::SessionMemory, append: nil, last_turns: []) }
  let(:tracer) { instance_double(Devagent::Tracer, event: nil) }
  let(:context) do
    instance_double(
      Devagent::Context,
      session_memory: session_memory,
      tracer: tracer
    )
  end

  subject(:streamer) { described_class.new(context, output: output) }

  describe "#with_stream" do
    it "buffers tokens and appends them to session memory" do
      result = streamer.with_stream(:planner) do |on_token|
        on_token.call("Hello ")
        on_token.call("world")
        "Hello world"
      end

      expect(result).to eq("Hello world")
      expect(session_memory).to have_received(:append).with("assistant", "Hello world")
    end
  end

  describe "#say" do
    it "logs coloured output and records in memory" do
      streamer.say("All good", level: :success)

      expect(session_memory).to have_received(:append).with("assistant", "All good")
      expect(tracer).to have_received(:event).with("log", message: "All good", level: :success)
    end
  end
end
