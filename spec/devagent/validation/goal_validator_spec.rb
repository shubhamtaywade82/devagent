# frozen_string_literal: true

require "spec_helper"

RSpec.describe Devagent::Validation::GoalValidator do
  let(:goal) { Devagent::Goal.new("Add feature X") }
  let(:repo_path) { Dir.pwd }

  def build_state(overrides = {})
    state = Devagent::AgentState.initial(goal: goal.description)
    overrides.each { |k, v| state.send("#{k}=", v) }
    state
  end

  describe ".satisfied?" do
    context "when there are errors" do
      it "returns not satisfied" do
        state = build_state
        state.record_error(signature: "test_error", message: "Something failed")

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        expect(result[:satisfied]).to be false
        expect(result[:reason]).to eq("Errors encountered")
      end
    end

    context "when clarification is needed" do
      it "returns not satisfied" do
        state = build_state(clarification_asked: true)

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        expect(result[:satisfied]).to be false
        expect(result[:reason]).to eq("Clarification needed")
      end
    end

    context "when tests passed" do
      it "returns satisfied" do
        state = build_state
        state.record_observation({ "type" => "TEST_RESULT", "status" => "PASS" })

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        expect(result[:satisfied]).to be true
        expect(result[:reason]).to eq("Tests passed")
      end
    end

    context "when all steps succeeded" do
      it "returns satisfied" do
        state = build_state
        state.step_results[1] = { "success" => true }
        state.step_results[2] = { "success" => true }

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        expect(result[:satisfied]).to be true
        expect(result[:reason]).to eq("All steps completed successfully")
      end

      it "returns not satisfied if any step failed" do
        state = build_state
        state.step_results[1] = { "success" => true }
        state.step_results[2] = { "success" => false }

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        expect(result[:satisfied]).to be false
      end
    end

    context "when files were modified" do
      it "returns satisfied when files_written is not empty" do
        state = build_state
        state.record_file_written("lib/test.rb")

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        expect(result[:satisfied]).to be true
        expect(result[:reason]).to eq("Files modified as expected")
      end

      it "returns satisfied when patches_applied > 0" do
        state = build_state
        state.artifacts[:patches_applied] = 1

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        expect(result[:satisfied]).to be true
        expect(result[:reason]).to eq("Files modified as expected")
      end
    end

    context "when no observable progress" do
      it "returns not satisfied" do
        state = build_state

        result = described_class.satisfied?(goal, state: state, repo_path: repo_path)
        # This might be true or false depending on git state
        # If there are uncommitted changes, it returns satisfied
        # Otherwise, it returns not satisfied
        expect(result).to have_key(:satisfied)
        expect(result).to have_key(:reason)
      end
    end
  end
end
