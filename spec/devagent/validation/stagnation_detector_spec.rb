# frozen_string_literal: true

require "spec_helper"

RSpec.describe Devagent::Validation::StagnationDetector do
  subject(:detector) { described_class.new }

  describe "#record_state" do
    it "records diff fingerprint" do
      detector.record_state(diff: "some diff content")
      expect(detector.stagnant?[:stagnant]).to be false
    end

    it "records plan fingerprint" do
      detector.record_state(plan_fingerprint: "abc123")
      expect(detector.stagnant?[:stagnant]).to be false
    end

    it "records observations" do
      detector.record_state(observations: [{ "type" => "TEST" }])
      expect(detector.stagnant?[:stagnant]).to be false
    end
  end

  describe "#stagnant?" do
    context "with insufficient history" do
      it "returns not stagnant" do
        detector.record_state(diff: "first diff")

        result = detector.stagnant?
        expect(result[:stagnant]).to be false
        expect(result[:reason]).to eq("Insufficient history")
      end
    end

    context "when same diff is repeated" do
      it "returns stagnant" do
        detector.record_state(diff: "same content")
        detector.record_state(diff: "same content")

        result = detector.stagnant?
        expect(result[:stagnant]).to be true
        expect(result[:reason]).to eq("Same diff repeated")
      end
    end

    context "when same plan is repeated" do
      it "returns stagnant" do
        detector.record_state(diff: "diff1", plan_fingerprint: "plan_abc")
        detector.record_state(diff: "diff2", plan_fingerprint: "plan_abc")

        result = detector.stagnant?
        expect(result[:stagnant]).to be true
        expect(result[:reason]).to eq("Same plan repeated")
      end
    end

    context "when making progress" do
      it "returns not stagnant" do
        detector.record_state(diff: "diff1", plan_fingerprint: "plan1")
        detector.record_state(diff: "diff2", plan_fingerprint: "plan2")

        result = detector.stagnant?
        expect(result[:stagnant]).to be false
        expect(result[:reason]).to eq("Making progress")
      end
    end
  end

  describe ".same_diff?" do
    it "returns true for identical diffs" do
      expect(described_class.same_diff?("same", "same")).to be true
    end

    it "returns false for different diffs" do
      expect(described_class.same_diff?("diff1", "diff2")).to be false
    end

    it "handles nil values" do
      expect(described_class.same_diff?(nil, nil)).to be true
      expect(described_class.same_diff?("", "")).to be true
      expect(described_class.same_diff?(nil, "something")).to be false
    end
  end

  describe "#reset!" do
    it "clears all history" do
      detector.record_state(diff: "same")
      detector.record_state(diff: "same")
      expect(detector.stagnant?[:stagnant]).to be true

      detector.reset!

      # After reset, insufficient history
      detector.record_state(diff: "new")
      expect(detector.stagnant?[:stagnant]).to be false
    end
  end
end
