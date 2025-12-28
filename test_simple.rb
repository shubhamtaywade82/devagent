#!/usr/bin/env ruby
# frozen_string_literal: true

# DevAgent Simple End-to-End Test
# This script tests DevAgent's core functionality without requiring external services

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "devagent"
require_relative "lib/devagent/ui"
require "json"
require "tempfile"
require "fileutils"

class SimpleDevAgentTest
  def initialize
    @test_dir = Dir.mktmpdir("devagent_simple_test")
    @original_dir = Dir.pwd
    @results = {}
  end

  def run_all_tests
    puts "🚀 DevAgent Simple End-to-End Test"
    puts "=" * 40

    Dir.chdir(@test_dir) do
      setup_test_environment

      test_context_building
      test_safety_features
      test_file_operations
      test_ui_components
      test_tool_registry
    end

    display_results
    cleanup
  end

  private

  def setup_test_environment
    puts "\n📁 Setting up test environment..."

    # Create a minimal test project
    FileUtils.mkdir_p("src")
    File.write("src/main.rb", <<~RUBY)
      class Calculator
        def add(a, b)
          a + b
        end
      end
    RUBY

    File.write("README.md", "# Test Project")

    # Create .devagent.yml with ollama (no API key needed)
    File.write(".devagent.yml", <<~YAML)
      provider: ollama
      model: llama3.2
      planner_model: llama3.2
      developer_model: llama3.2
      reviewer_model: llama3.2
      embed_model: nomic-embed-text
      auto:
        allowlist:
          - "**/*"
        denylist: []
    YAML

    puts "✅ Test environment created"
  end

  def test_context_building
    puts "\n🔧 Testing Context Building..."

    begin
      context = Devagent::Context.build(Dir.pwd)

      @results[:context_building] = {
        status: "PASS",
        provider: context.resolved_provider,
        repo_path: context.repo_path
      }

      puts "✅ Context built successfully"
      puts "   Provider: #{context.resolved_provider}"
      puts "   Repo path: #{context.repo_path}"
    rescue StandardError => e
      @results[:context_building] = { status: "FAIL", error: e.message }
      puts "❌ Context building failed: #{e.message}"
    end
  end

  def test_safety_features
    puts "\n🛡️  Testing Safety Features..."

    begin
      context = Devagent::Context.build(Dir.pwd)
      safety = Devagent::Safety.new(context)

      # Test allowed paths
      allowed = safety.allowed?("src/main.rb")
      denied_absolute = safety.allowed?("/etc/passwd")
      denied_git = safety.allowed?(".git/config")

      if allowed && !denied_absolute && !denied_git
        @results[:safety_features] = { status: "PASS" }
        puts "✅ Safety features working correctly"
        puts "   Allowed paths: ✅"
        puts "   Denied absolute paths: ✅"
        puts "   Denied git paths: ✅"
      else
        @results[:safety_features] = { status: "FAIL", error: "Safety checks not working properly" }
        puts "❌ Safety features failed"
      end
    rescue StandardError => e
      @results[:safety_features] = { status: "FAIL", error: e.message }
      puts "❌ Safety features test failed: #{e.message}"
    end
  end

  def test_file_operations
    puts "\n📝 Testing File Operations..."

    begin
      context = Devagent::Context.build(Dir.pwd)
      tool_bus = Devagent::ToolBus.new(context, registry: Devagent::ToolRegistry.default)

      # Test file writing
      test_content = "# Test file created by DevAgent\necho 'Hello from DevAgent!'"
      result = tool_bus.write_file({
                                     "path" => "test_output.rb",
                                     "content" => test_content
                                   })

      # Verify file was created
      if File.exist?("test_output.rb") && File.read("test_output.rb") == test_content
        @results[:file_operations] = { status: "PASS" }
        puts "✅ File operations working correctly"
        puts "   Created test_output.rb successfully"
        puts "   Content matches expected"
      else
        @results[:file_operations] = { status: "FAIL", error: "File not created or content mismatch" }
        puts "❌ File operations failed"
      end
    rescue StandardError => e
      @results[:file_operations] = { status: "FAIL", error: e.message }
      puts "❌ File operations test failed: #{e.message}"
    end
  end

  def test_ui_components
    puts "\n🎨 Testing UI Components..."

    begin
      # Test UI toolkit
      ui = Devagent::UI::Toolkit.new

      # Test spinner
      spinner = ui.spinner("Testing UI...")
      spinner.run { "UI test completed" }

      # Test table
      table = ui.table(
        header: %w[Component Status],
        rows: [["UI Toolkit", "Working"], ["Spinner", "Working"], ["Table", "Working"]]
      )

      # Test colorizer
      colorizer = ui.colorizer
      colored_text = colorizer.colorize(:success, "Success!")

      @results[:ui_components] = { status: "PASS" }
      puts "✅ UI components working correctly"
      puts "   Spinner: ✅"
      puts "   Table: ✅"
      puts "   Colorizer: ✅"
    rescue StandardError => e
      @results[:ui_components] = { status: "FAIL", error: e.message }
      puts "❌ UI components test failed: #{e.message}"
    end
  end

  def test_tool_registry
    puts "\n🔧 Testing Tool Registry..."

    begin
      registry = Devagent::ToolRegistry.default

      # Test tool registration and validation
      read_tool = registry.validate!("fs.read", { "path" => "README.md" })

      if read_tool && read_tool.handler == :read_file
        @results[:tool_registry] = { status: "PASS" }
        puts "✅ Tool registry working correctly"
        puts "   Tool validation: ✅"
        puts "   Handler mapping: ✅"
      else
        @results[:tool_registry] = { status: "FAIL", error: "Tool registry not working properly" }
        puts "❌ Tool registry failed"
      end
    rescue StandardError => e
      @results[:tool_registry] = { status: "FAIL", error: e.message }
      puts "❌ Tool registry test failed: #{e.message}"
    end
  end

  def display_results
    puts "\n" + ("=" * 40)
    puts "📊 TEST RESULTS SUMMARY"
    puts "=" * 40

    @results.each do |test_name, result|
      status = result[:status]
      case status
      when "PASS"
        puts "✅ #{test_name.to_s.tr("_", " ").capitalize}: PASS"
      when "FAIL"
        puts "❌ #{test_name.to_s.tr("_", " ").capitalize}: FAIL"
        puts "   Error: #{result[:error]}" if result[:error]
      end
    end

    passed = @results.count { |_, r| r[:status] == "PASS" }
    total = @results.size

    puts "\n🎯 Overall Result: #{passed}/#{total} tests passed"

    if passed == total
      puts "🎉 All tests passed! DevAgent core functionality is working."
    elsif passed > total / 2
      puts "⚠️  Most tests passed. DevAgent is mostly functional."
    else
      puts "❌ Multiple tests failed. DevAgent needs attention."
    end

    puts "\n💡 Note: This test focuses on core functionality without external dependencies."
    puts "   For full LLM testing, ensure you have Ollama running or OpenAI API key set."
  end

  def cleanup
    FileUtils.rm_rf(@test_dir)
    Dir.chdir(@original_dir)
    puts "\n🧹 Test environment cleaned up"
  end
end

# Run the tests
if __FILE__ == $0
  test = SimpleDevAgentTest.new
  test.run_all_tests
end
