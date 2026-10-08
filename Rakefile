# frozen_string_literal: true

require 'rake'
require 'bundler/gem_tasks'
require 'yaml'

# Load DocOps Lab development tasks
begin
  require 'docopslab/dev'
rescue LoadError
  # Skip if not available (e.g., production environment)
end

VERSION_LINE_REGEX = /^:this_prod_vrsn:\s+(.*)$/

DOCS_MANIFEST_PATH = File.join(__dir__, 'specs/data/docs-manifest.yml')
DOCS_MANIFEST_PATH_KEYS = %i[template data out attrs].freeze

namespace :generate do
  desc 'Generate reference docs from templates + data, per specs/data/docs-manifest.yml'
  task :docs do
    require_relative 'lib/sourcerer'

    manifest = YAML.safe_load_file(DOCS_MANIFEST_PATH, permitted_classes: [Date, Time])
    entries = manifest['docs'] || []

    entries.each do |entry|
      render_entry = entry.transform_keys(&:to_sym)
      DOCS_MANIFEST_PATH_KEYS.each do |key|
        next unless render_entry[key]

        render_entry[key] = File.expand_path(render_entry[key], __dir__)
      end

      puts "Generating #{render_entry[:name] || render_entry[:out]} -> #{render_entry[:out]}"
      Sourcerer::Rendering.render_outputs([render_entry])
    end
  end

  desc 'Regenerate and locally commit the documentation branch (does not push)'
  task :documentation do
    sh 'ruby scripts/build_docs.rb'
  end
end

# The lib/sourcerer/_docs/ is generated, thus git-ignored. This enhances
# the build task defined by bundler/gem_tasks (rather than redefining it),
# regenerates those docs immediately before the gem is built, so they're
# present on disk and picked up by the gemspec's `Dir[]` glob by the
# time `gem build` runs.
task build: 'generate:docs'

# Only require rspec when running spec tasks
begin
  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:rspec) do |t|
    t.pattern = 'specs/tests/rspec/**/*_spec.rb'
  end

  desc 'Validate YAML fixtures and loader behavior'
  task :yaml_test do
    require_relative 'lib/sourcerer/yaml'

    tags_path = File.join(__dir__, 'specs/tests/fixtures/yaml-with-tags.yml')
    attrs_path = File.join(__dir__, 'specs/tests/fixtures/yaml-with-attrs.yml')

    data = Sourcerer::Yaml.load_with_tags(tags_path)
    raise 'YAML tag preservation failed for title' unless data['title'].is_a?(Hash)

    attrs = { 'default_markup' => 'markdown' }
    data = Sourcerer::Yaml.load_with_attributes(attrs_path, attrs)
    dflt = data.dig('properties', '$meta', 'properties', 'markup', 'dflt')
    raise 'YAML attribute resolution failed for default_markup' unless dflt == 'markdown'
  end

  desc 'Run CI/PR test suite'
  task pr_test: %i[rspec yaml_test]

  task default: :rspec
rescue LoadError
  # RSpec not available - skip test tasks
end
