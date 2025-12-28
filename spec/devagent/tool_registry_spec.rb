# frozen_string_literal: true

RSpec.describe Devagent::ToolRegistry do
  subject(:registry) { described_class.default }

  describe "#visible_tools_for_phase" do
    it "returns only non-internal tools for planning" do
      names = registry.visible_tools_for_phase(:planning).map(&:name)

      expect(names).to include("fs.read", "fs.write", "exec.run", "diagnostics.error_summary", "fs.delete")
      expect(names).not_to include("fs.write_diff")
    end
  end

  describe "#validate!" do
    it "validates inputs schema for fs.read" do
      expect {
        registry.validate!("fs.read", {})
      }.to raise_error(JSON::Schema::ValidationError)
    end

    it "raises on unknown tool" do
      expect {
        registry.validate!("nope.tool", {})
      }.to raise_error(Devagent::Error, /Unknown tool/)
    end
  end
end

