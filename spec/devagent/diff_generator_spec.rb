# frozen_string_literal: true

RSpec.describe Devagent::DiffGenerator do
  let(:context) { instance_double(Devagent::Context) }

  describe "#generate" do
    let(:path) { "lib/example.rb" }
    let(:original) { "line1\nline2\nline3\n" }
    let(:goal) { "Add a comment at the top" }
    let(:file_exists) { true }

    context "when adding a top comment but one already exists" do
      let(:original) { "# Added comment\nline1\nline2\n" }

      it "returns a valid no-op diff without calling the LLM" do
        expect(context).not_to receive(:query)

        diff = described_class.new(context).generate(
          path: path,
          original: original,
          goal: goal,
          reason: "add a comment at the top",
          file_exists: file_exists
        )

        expect(diff).to include("--- a/#{path}")
        expect(diff).to include("+++ b/#{path}")
        expect(diff).to include("@@")
      end
    end

    context "when the model returns headers but no hunk markers" do
      let(:llm_response) do
        <<~DIFF
          --- a/#{path}
          +++ b/#{path}
          +# Added comment
        DIFF
      end

      it "inserts a @@ hunk header as a fallback" do
        allow(context).to receive(:query).and_return(llm_response)

        diff = described_class.new(context).generate(
          path: path,
          original: original,
          goal: goal,
          reason: "add a comment at the top",
          file_exists: file_exists
        )

        expect(diff).to include("@@")
      end
    end

    context "when the model returns no diff at all" do
      let(:llm_response) { "" }

      it "constructs a minimal valid unified diff" do
        allow(context).to receive(:query).and_return(llm_response)

        diff = described_class.new(context).generate(
          path: path,
          original: original,
          goal: "Make some change",
          reason: "change something",
          file_exists: file_exists
        )

        expect(diff).to include("--- a/#{path}")
        expect(diff).to include("+++ b/#{path}")
        expect(diff).to include("@@")
      end
    end

    context "when the model wraps the diff in markdown fences" do
      let(:llm_response) do
        <<~DIFF
          ```diff
          --- a/#{path}
          +++ b/#{path}
          @@ -1,1 +1,2 @@
          +# Added
           line1
          ```
        DIFF
      end

      it "strips the fences" do
        allow(context).to receive(:query).and_return(llm_response)

        diff = described_class.new(context).generate(
          path: path,
          original: original,
          goal: goal,
          reason: "add a comment at the top",
          file_exists: file_exists
        )

        expect(diff).to start_with("--- a/#{path}")
        expect(diff).not_to include("```")
      end
    end
  end
end

