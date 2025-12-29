# frozen_string_literal: true

require "tmpdir"

RSpec.describe Devagent::Tracer do
  it "writes events and debug messages to a JSONL file" do
    Dir.mktmpdir do |dir|
      tracer = described_class.new(dir)
      tracer.event("test", a: 1)
      tracer.debug("hello")

      content = File.read(tracer.path, encoding: "UTF-8")
      expect(content).to include('"type":"test"')
      expect(content).to include('"type":"debug"')
    end
  end

  it "never raises if tracing fails to write" do
    Dir.mktmpdir do |dir|
      tracer = described_class.new(dir)
      # Force writes to fail by pointing at a directory.
      tracer.instance_variable_set(:@path, File.join(dir, ".devagent"))

      expect { tracer.event("test") }.not_to raise_error
      expect(tracer.event("test")).to be_nil
    end
  end
end

