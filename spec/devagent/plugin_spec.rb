# frozen_string_literal: true

RSpec.describe Devagent::Plugin do
  it "provides safe defaults for plugin hooks" do
    expect(described_class.applies?("/workspace")).to be(false)
    expect(described_class.priority).to eq(0)
    expect(described_class.on_prompt(nil, "task")).to eq("")
    expect(described_class.on_action(nil, "tool", {})).to be_nil
    expect(described_class.commands).to eq({})
    expect(described_class.test_command(nil)).to be_nil
  end
end

