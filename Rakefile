# frozen_string_literal: true

require 'rake'
require 'yaml'

# Load DocOps Lab development tasks
begin
  require 'docopslab/dev'
rescue LoadError
  # Skip if not available (e.g., production environment)
end

VERSION_LINE_REGEX = /^:this_prod_vrsn:\s+(.*)$/

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
