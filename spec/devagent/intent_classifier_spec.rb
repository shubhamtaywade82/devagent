# frozen_string_literal: true

RSpec.describe Devagent::IntentClassifier do
  let(:context) { instance_double(Devagent::Context) } # no query/provider_for => heuristic path

  subject(:classifier) { described_class.new(context) }

  it "returns REJECT for empty input" do
    expect(classifier.classify("")).to include("intent" => "REJECT")
  end

  it "detects DEBUG intent from error words" do
    expect(classifier.classify("tests are failing with an exception")).to include("intent" => "DEBUG")
  end

  it "detects CODE_REVIEW intent from review words" do
    expect(classifier.classify("review this code for issues")).to include("intent" => "CODE_REVIEW")
  end

  it "detects CODE_EDIT intent from action verbs" do
    expect(classifier.classify("add a new class")).to include("intent" => "CODE_EDIT")
  end

  it "detects EXPLANATION intent from questions" do
    expect(classifier.classify("what does this do?")).to include("intent" => "EXPLANATION")
  end

  it "falls back to GENERAL otherwise" do
    expect(classifier.classify("hello there")).to include("intent" => "GENERAL")
  end
end

