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

  describe "#tools_for_phase" do
    it "returns a name=>tool hash for planning tools" do
      tools = registry.tools_for_phase(:planning)
      expect(tools).to be_a(Hash)
      expect(tools.keys).to include("fs.read", "fs.write")
      expect(tools.keys).not_to include("fs.write_diff")
    end
  end

  describe Devagent::ToolRegistry::Tool do
    it "exposes a compact contract hash for planner injection" do
      tool = described_class.new(
        name: "x",
        category: "test",
        description: "d",
        purpose: "p",
        when_to_use: ["a"],
        when_not_to_use: ["b"],
        inputs_schema: { "type" => "object" },
        outputs_schema: { "type" => "object" },
        dependencies: { "required_tools" => [] },
        side_effects: [],
        safety_rules: [],
        examples: {},
        internal: false
      )

      contract = tool.to_contract_hash
      expect(contract).to include("name" => "x", "category" => "test", "description" => "d")
      expect(contract).to have_key("inputs")
      expect(contract).to have_key("outputs")
    end

    it "honors forbidden and allowed phases" do
      tool = described_class.new(
        name: "x",
        category: "test",
        description: "d",
        inputs_schema: nil,
        outputs_schema: nil,
        allowed_phases: [:execution],
        forbidden_phases: [:planning],
        internal: false
      )

      expect(tool.allowed_in_phase?(:planning)).to be(false)
      expect(tool.allowed_in_phase?(:execution)).to be(true)
    end
  end

  describe "#validate!" do
    it "validates inputs schema for fs.read" do
      expect do
        registry.validate!("fs.read", {})
      end.to raise_error(JSON::Schema::ValidationError)
    end

    it "raises on unknown tool" do
      expect do
        registry.validate!("nope.tool", {})
      end.to raise_error(Devagent::Error, /Unknown tool/)
    end
  end
end
