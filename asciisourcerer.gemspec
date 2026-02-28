# frozen_string_literal: true

require_relative 'lib/sourcerer/version'

Gem::Specification.new do |spec|
  spec.name          = 'asciisourcerer'
  spec.version       = Sourcerer::VERSION || '0.0.0-alpha'
  spec.authors       = ['DocOps Lab']
  spec.email         = ['docopslab@protonmail.com']

  spec.summary       = 'APIs for specialized handling of AsciiDoc, YAML, and Liquid documents.'
  spec.description   = [
    'AsciiSourcerer provides APIs for specialized use of AsciiDoc (attribute extraction, special conversions),',
    'YAML (tag handling), and Liquid (Jekyll-based rendering, custom tags, etc).'
  ].join(' ')
  spec.homepage      = 'https://github.com/DocOps/asciisourcerer'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb', 'README.adoc', 'LICENSE', 'specs/docs/**/*.adoc']
  spec.require_paths = ['lib']

  # Development dependencies are in Gemfile per RuboCop best practices

  spec.add_dependency 'asciidoctor', '~> 2.0'
  spec.add_dependency 'asciidoctor-html5s', '~> 0.5'
  spec.add_dependency 'jekyll', '~> 4.4'
  spec.add_dependency 'jekyll-asciidoc', '~> 3.0'
  spec.add_dependency 'kramdown-asciidoc', '~> 2.1'
  spec.add_dependency 'liquid', '~> 4.0'
  spec.add_dependency 'reverse_markdown', '~> 2.1'
end
