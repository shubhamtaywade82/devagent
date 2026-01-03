# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Devagent::Util do
  describe ".run!" do
    it "runs a command successfully (array form)" do
      out = described_class.run!(["bash", "-lc", "echo hi"]).strip
      expect(out).to eq("hi")
    end

    it "raises on non-zero exit" do
      expect do
        described_class.run!(["bash", "-lc", "echo err 1>&2; exit 1"])
      end.to raise_error(/Command failed/)
    end
  end

  describe ".run_capture" do
    it "captures stdout/stderr/exit_code even on failure" do
      res = described_class.run_capture(["bash", "-lc", "echo out; echo err 1>&2; exit 2"])
      expect(res).to include("exit_code" => 2, "success" => false)
      expect(res["stdout"]).to include("out")
      expect(res["stderr"]).to include("err")
    end
  end

  describe ".text_file?" do
    it "returns false for missing files" do
      expect(described_class.text_file?("/workspace/spec/missing___util.txt")).to be(false)
    end

    it "detects plain text files" do
      # Use a temporary directory that we can actually create
      tmp_dir = Dir.mktmpdir
      path = File.join(tmp_dir, "tmp_text___util.txt")
      File.write(path, "hello\nworld\n", encoding: "UTF-8")
      expect(described_class.text_file?(path)).to be(true)
    ensure
      File.delete(path) if path && File.exist?(path)
      FileUtils.rm_rf(tmp_dir) if defined?(tmp_dir) && tmp_dir && Dir.exist?(tmp_dir)
    end

    it "detects binary-ish files" do
      # Use a temporary directory that we can actually create
      tmp_dir = Dir.mktmpdir
      path = File.join(tmp_dir, "tmp_bin___util.bin")
      File.binwrite(path, "\x00" * 512)
      expect(described_class.text_file?(path)).to be(false)
    ensure
      File.delete(path) if path && File.exist?(path)
      FileUtils.rm_rf(tmp_dir) if defined?(tmp_dir) && tmp_dir && Dir.exist?(tmp_dir)
    end
  end
end
