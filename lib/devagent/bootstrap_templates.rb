# frozen_string_literal: true

require "json"

module Devagent
  # BootstrapTemplates provides deterministic, controller-owned scaffolds for devagent init.
  #
  # Templates are intentionally minimal (production-grade defaults without guessing).
  module BootstrapTemplates
    module_function

    def normalize_project_name(name)
      n = name.to_s.strip
      n = "my_project" if n.empty?
      n = n.downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
      n = "my_project" if n.empty?
      n
    end

    def ruby_module_name(project_name)
      project_name
        .split(/[_\-]/)
        .map { |part| part.sub(/\A\p{Lower}/) { |c| c.upcase } }
        .join
    end

    def plan_for(kind:, language:, tests:, project_name:)
      name = normalize_project_name(project_name)
      kind = kind.to_s
      language = language.to_s
      tests = tests == true

      case [kind, language]
      when ["Ruby gem", "Ruby"]
        ruby_gem_plan(name: name, tests: tests)
      when ["Rails app", "Ruby"]
        rails_app_plan(name: name, tests: tests)
      when ["Script / utility", "Ruby"]
        ruby_script_plan(name: name, tests: tests)
      when ["Script / utility", "JS/TS"]
        node_script_plan(name: name, tests: tests)
      else
        generic_plan(name: name)
      end
    end

    def ruby_gem_plan(name:, tests:)
      mod = ruby_module_name(name)
      gemspec_name = "#{name}.gemspec"

      files = []
      files << ["README.md", <<~MD]
        # #{mod}

        TODO: Describe this gem.

        ## Installation

        Add this line to your application's Gemfile:

        ```ruby
        gem "#{name}"
        ```

        And then execute:

        ```bash
        bundle install
        ```

        ## Usage

        TODO: Add usage examples.
      MD

      files << [gemspec_name, <<~RUBY]
        # frozen_string_literal: true

        require_relative "lib/#{name}/version"

        Gem::Specification.new do |spec|
          spec.name          = "#{name}"
          spec.version       = #{mod}::VERSION
          spec.authors       = ["TODO: Your Name"]
          spec.email         = ["TODO: your.email@example.com"]

          spec.summary       = "TODO: Summary of #{name}."
          spec.description   = "TODO: Description of #{name}."
          spec.homepage      = "TODO: Homepage URL"
          spec.license       = "MIT"
          spec.required_ruby_version = ">= 3.1.0"

          spec.files = Dir.glob("{lib}/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
          spec.require_paths = ["lib"]

          spec.metadata["rubygems_mfa_required"] = "true"

          spec.add_development_dependency "rake", "~> 13.0"
          spec.add_development_dependency "rspec", "~> 3.13"
        end
      RUBY

      files << ["Gemfile", <<~RUBY]
        # frozen_string_literal: true

        source "https://rubygems.org"

        gemspec

        gem "rake", "~> 13.0"
        gem "rspec", "~> 3.13"
      RUBY

      files << [".gitignore", <<~TXT]
        /.bundle/
        /.devagent/
        /vendor/
        /tmp/
        *.gem
        *.log
      TXT

      files << ["lib/#{name}.rb", <<~RUBY]
        # frozen_string_literal: true

        require_relative "#{name}/version"

        module #{mod}
          class Error < StandardError; end
        end
      RUBY

      files << ["lib/#{name}/version.rb", <<~RUBY]
        # frozen_string_literal: true

        module #{mod}
          VERSION = "0.1.0"
        end
      RUBY

      files << ["Rakefile", <<~RUBY]
        # frozen_string_literal: true

        require "rake"

        desc "Run specs"
        task :spec do
          sh "bundle exec rspec"
        end

        task default: :spec
      RUBY

      if tests
        files << ["spec/spec_helper.rb", <<~RUBY]
          # frozen_string_literal: true

          require "#{name}"

          RSpec.configure do |config|
            config.disable_monkey_patching!
            config.expect_with :rspec do |c|
              c.syntax = :expect
            end
          end
        RUBY

        files << ["spec/#{name}_spec.rb", <<~RUBY]
          # frozen_string_literal: true

          RSpec.describe #{mod} do
            it "has a version number" do
              expect(#{mod}::VERSION).not_to be_nil
            end
          end
        RUBY
      end

      build_plan("bootstrap_ruby_gem", files)
    end

    def rails_app_plan(name:, tests:)
      # Intentionally minimal: bootstrap rails dependencies + a README that instructs next steps.
      # A full "rails new" scaffold is too large/noisy for a deterministic fs.create-only bootstrap.
      mod = ruby_module_name(name)
      files = []
      files << ["README.md", <<~MD]
        # #{mod}

        This repository was bootstrapped by `devagent init`.

        ## Next steps

        1. Ensure Ruby is installed (>= 3.1).
        2. Run:

           ```bash
           bundle install
           bundle exec rails new . --force --skip-git
           ```

        3. Commit the generated scaffold.
      MD

      files << ["Gemfile", <<~RUBY]
        # frozen_string_literal: true

        source "https://rubygems.org"

        ruby "3.2.0"

        gem "rails", "~> 7.1"
      RUBY

      files << [".gitignore", <<~TXT]
        /.bundle/
        /.devagent/
        /log/
        /tmp/
        /vendor/
      TXT

      files << [".ruby-version", "3.2.0\n"]

      files << ["spec/README.md", <<~MD] if tests
        # Specs

        You opted into tests during bootstrap.
        Once Rails is generated, add RSpec (or Minitest) and configure CI.
      MD

      build_plan("bootstrap_rails_app", files)
    end

    def ruby_script_plan(name:, tests:)
      mod = ruby_module_name(name)
      files = []
      files << ["README.md", <<~MD]
        # #{mod}

        Minimal Ruby utility bootstrapped by `devagent init`.
      MD

      files << ["lib/#{name}.rb", <<~RUBY]
        # frozen_string_literal: true

        module #{mod}
          def self.run(argv)
            puts "hello from #{mod}"
            argv
          end
        end
      RUBY

      files << ["bin/#{name}", <<~RUBY]
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        require_relative "../lib/#{name}"

        #{mod}.run(ARGV)
      RUBY

      files << [".gitignore", "/.devagent/\n/.bundle/\n/tmp/\n"]

      if tests
        files << ["spec/spec_helper.rb", <<~RUBY]
          # frozen_string_literal: true

          require "#{name}"
        RUBY
      end

      build_plan("bootstrap_ruby_script", files)
    end

    def node_script_plan(name:, tests:)
      files = []
      files << ["README.md", <<~MD]
        # #{name}

        Minimal Node utility bootstrapped by `devagent init`.
      MD

      pkg = {
        "name" => name,
        "private" => true,
        "type" => "module",
        "scripts" => {
          "start" => "node src/index.js"
        }
      }
      pkg["scripts"]["test"] = "node --test" if tests

      files << ["package.json", JSON.pretty_generate(pkg) + "\n"]
      files << ["src/index.js", "console.log('hello');\n"]
      files << [".gitignore", "/.devagent/\n/node_modules/\n/dist/\n"]

      build_plan("bootstrap_node_script", files)
    end

    def generic_plan(name:)
      files = []
      files << ["README.md", "# #{ruby_module_name(name)}\n\nBootstrapped by `devagent init`.\n"]
      files << [".gitignore", "/.devagent/\n"]
      build_plan("bootstrap_generic", files)
    end

    def build_plan(plan_id, files)
      steps = files.each_with_index.map do |(path, content), idx|
        {
          "step_id" => idx + 1,
          "action" => "fs.create",
          "path" => path,
          "command" => nil,
          "content" => content.to_s,
          "reason" => "Bootstrap file",
          "depends_on" => [0]
        }
      end

      {
        "plan_id" => plan_id,
        "steps" => steps,
        "confidence" => 0.9
      }
    end
  end
end

