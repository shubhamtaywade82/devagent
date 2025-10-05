#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showcasing the enhanced DevAgent UI components
require_relative "lib/devagent/ui"

puts "🚀 DevAgent Enhanced UI Components Demo"
puts "=" * 50

ui = Devagent::UI::Toolkit.new

# 1. Box Component Demo
puts "\n📦 Box Component Demo:"
ui.box.info("Plan Summary",
            "This is a comprehensive plan:\n1. Analyze codebase structure\n2. Generate comprehensive tests\n3. Run validation suite\n4. Deploy changes")
ui.box.success("Operation Complete", "All tests passed successfully!\n✅ 15 tests run\n✅ 0 failures\n✅ Coverage: 95%")

# 2. Markdown Renderer Demo
puts "\n📝 Markdown Renderer Demo:"
markdown_content = <<~MARKDOWN
  # DevAgent Enhanced UI

  This demonstrates the **powerful** markdown rendering capabilities:

  - **Bold text** and *italic text*
  - `Code snippets` and `inline code`
  - Lists and structured content

  ## Features

  - Streaming markdown output
  - Real-time cursor management
  - Beautiful terminal formatting
MARKDOWN

puts ui.markdown_renderer.render_static(markdown_content)

# 3. Progress Bar Demo
puts "\n📊 Progress Bar Demo:"
progress_bar = ui.progress.embedding_index(100)
5.times do |i|
  sleep(0.2)
  progress_bar.advance(20)
end
progress_bar.finish

# 4. Spinner Demo
puts "\n⏳ Spinner Demo:"
spinner = ui.spinner("Processing files")
spinner.run do
  sleep(1)
  "Processed 25 files successfully"
end

# 5. Table Demo
puts "\n📋 Table Demo:"
rows = [
  ["Provider", "OpenAI"],
  ["Planner Model", "gpt-4o-mini"],
  ["Developer Model", "gpt-4o-mini"],
  ["Reviewer Model", "gpt-4o"],
  ["Embedding Model", "text-embedding-3-small"],
  ["Index Size", "217 chunks"]
]
table = ui.table(header: %w[Component Value], rows: rows)
table.render

# 6. Command Demo
puts "\n⚙️ Command Demo:"
result = ui.command.run("echo 'Hello from DevAgent Command!'", verbose: true)
puts "Command result: #{result.stdout.strip}"

puts "\n🎉 Demo Complete! All enhanced UI components are working perfectly."
