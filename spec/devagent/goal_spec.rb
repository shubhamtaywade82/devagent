# frozen_string_literal: true

require "spec_helper"

RSpec.describe Devagent::Goal do
  describe ".new" do
    it "creates a goal with a description" do
      goal = described_class.new("Add a hello world function")
      expect(goal.description).to eq("Add a hello world function")
    end

    it "strips whitespace from description" do
      goal = described_class.new("  Add feature  ")
      expect(goal.description).to eq("Add feature")
    end

    it "raises ArgumentError for empty description" do
      expect { described_class.new("") }.to raise_error(ArgumentError, /cannot be empty/)
      expect { described_class.new("   ") }.to raise_error(ArgumentError, /cannot be empty/)
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /cannot be empty/)
    end

    it "sets created_at timestamp" do
      before = Time.now
      goal = described_class.new("Test goal")
      after = Time.now

      expect(goal.created_at).to be >= before
      expect(goal.created_at).to be <= after
    end
  end

  describe "#to_s" do
    it "returns the description" do
      goal = described_class.new("Build feature X")
      expect(goal.to_s).to eq("Build feature X")
    end
  end

  describe "#==" do
    it "returns true for goals with same description" do
      goal1 = described_class.new("Same goal")
      goal2 = described_class.new("Same goal")
      expect(goal1).to eq(goal2)
    end

    it "returns false for goals with different descriptions" do
      goal1 = described_class.new("Goal A")
      goal2 = described_class.new("Goal B")
      expect(goal1).not_to eq(goal2)
    end

    it "returns false when compared with non-Goal objects" do
      goal = described_class.new("Test goal")
      expect(goal).not_to eq("Test goal")
      expect(goal).not_to be_nil
    end
  end

  describe "#hash" do
    it "returns same hash for equal goals" do
      goal1 = described_class.new("Same goal")
      goal2 = described_class.new("Same goal")
      expect(goal1.hash).to eq(goal2.hash)
    end
  end
end
