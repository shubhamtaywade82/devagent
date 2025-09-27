# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Devagent::RepoSurvey do
  it "captures top-level structure, key files, and doc previews" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'")
      File.write(File.join(dir, "README.md"), "# Sample\nThis is a README.")

      survey = described_class.new(dir).capture!

      expect(survey.structure_lines).to include("lib/ (library runtime code)")
      expect(survey.structure_lines).to include("spec/ (RSpec tests)")
      expect(survey.key_file_lines).to include("Gemfile (Ruby dependencies)")
      expect(survey.doc_previews.keys).to include("README.md")
      expect(survey.summary_text).to include("Directories:")
    end
  end
end
