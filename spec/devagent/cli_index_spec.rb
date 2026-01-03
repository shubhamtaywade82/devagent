# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::CLI do
  let(:repo_path) { Dir.mktmpdir }

  before do
    # Create a sample file
    File.write(File.join(repo_path, "sample.rb"), "class Sample\nend\n")
    Dir.chdir(repo_path)
  end

  after do
    FileUtils.remove_entry(repo_path)
  end

  describe "#index" do
    it "responds to index command" do
      expect(described_class.new.respond_to?(:index)).to be true
    end

    it "has index as a valid command" do
      expect(described_class.commands).to have_key("index")
    end
  end
end
