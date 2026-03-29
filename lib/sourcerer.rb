# frozen_string_literal: true

require_relative 'sourcerer/version'
require_relative 'sourcerer/asciidoc'
require_relative 'sourcerer/builder'
require_relative 'sourcerer/plaintext_converter'
require_relative 'sourcerer/rendering'
require_relative 'sourcerer/templating'
require_relative 'sourcerer/yaml'

# Public API façade.
#
# This file intentionally provides a stable, high-level entry point while
# feature-specific behavior lives in dedicated namespaces under
# `Sourcerer::AsciiDoc`, `Sourcerer::Yaml`, and `Sourcerer::Rendering`.
#
# Requiring `sourcerer` also makes adjacent public constants (for example,
# `Sourcerer::Builder`) available to downstream callers.
module Sourcerer
  # File extensions recognised as Markdown source files.
  MARKDOWN_EXTS  = %w[.md .markdown].freeze

  # File extensions recognised as AsciiDoc source files.
  ASCIIDOC_EXTS  = %w[.adoc .asciidoc .asc .ad].freeze

  autoload :AttributesFilter, 'sourcerer/attributes_filter'
  autoload :YamlFrontmatter,     'sourcerer/yaml_frontmatter'
  autoload :Jekyll,              'sourcerer/jekyll'
  autoload :MarkDownGrade,       'sourcerer/mark_down_grade'
  autoload :SourceSkim,          'sourcerer/source_skim'
  autoload :Sync,                'sourcerer/sync'

  DEPRECATED_FACADE_METHODS = {
    # DO NOT add new public methods to this surface
    load_attributes: 'Sourcerer::AsciiDoc.load_attributes',
    load_include: 'Sourcerer::AsciiDoc.load_include',
    extract_tagged_content: 'Sourcerer::AsciiDoc.extract_tagged_content',
    generate_manpage: 'Sourcerer::AsciiDoc.generate_manpage',
    generate_html: 'Sourcerer::AsciiDoc.generate_html',
    extract_commands: 'Sourcerer::AsciiDoc.extract_commands',
    render_templates: 'Sourcerer::Rendering.render_templates',
    render_outputs: 'Sourcerer::Rendering.render_outputs',
    render_template: 'Sourcerer::Rendering.render_template',
    render_with_converter: 'Sourcerer::Rendering.render_with_converter'
  }.freeze

  def self.warn_deprecated_facade method_name
    @warned_deprecations ||= {}
    return if @warned_deprecations[method_name]

    replacement = DEPRECATED_FACADE_METHODS[method_name]
    warning_message = "DEPRECATION: Sourcerer.#{method_name} is deprecated and will be removed in Sourcerer 1.0; " \
                      "use #{replacement} instead."
    warn(warning_message)
    @warned_deprecations[method_name] = true
  end
  private_class_method :warn_deprecated_facade

  def self.load_attributes path
    warn_deprecated_facade(:load_attributes)
    Sourcerer::AsciiDoc.load_attributes(path)
  end

  def self.load_include path_to_main_adoc, tag: nil, tags: [], leveloffset: nil
    warn_deprecated_facade(:load_include)
    Sourcerer::AsciiDoc.load_include(
      path_to_main_adoc,
      tag: tag,
      tags: tags,
      leveloffset: leveloffset)
  end

  def self.extract_tagged_content path_to_tagged_adoc, **options
    warn_deprecated_facade(:extract_tagged_content)
    Sourcerer::AsciiDoc.extract_tagged_content(path_to_tagged_adoc, **options)
  end

  def self.generate_manpage source_adoc, target_manpage
    warn_deprecated_facade(:generate_manpage)
    Sourcerer::AsciiDoc.generate_manpage(source_adoc, target_manpage)
  end

  def self.generate_html source_adoc, target_html, backend: 'asciidoctor-html5s'
    warn_deprecated_facade(:generate_html)
    Sourcerer::AsciiDoc.generate_html(source_adoc, target_html, backend: backend)
  end

  def self.extract_commands file_path, role: 'testable'
    warn_deprecated_facade(:extract_commands)
    Sourcerer::AsciiDoc.extract_commands(file_path, role: role)
  end

  def self.render_templates templates_config
    warn_deprecated_facade(:render_templates)
    Sourcerer::Rendering.render_templates(templates_config)
  end

  def self.render_outputs render_config
    warn_deprecated_facade(:render_outputs)
    Sourcerer::Rendering.render_outputs(render_config)
  end

  def self.render_template template_file, data_file, out_file, **options
    warn_deprecated_facade(:render_template)
    Sourcerer::Rendering.render_template(template_file, data_file, out_file, **options)
  end

  def self.render_with_converter render_entry
    warn_deprecated_facade(:render_with_converter)
    Sourcerer::Rendering.render_with_converter(render_entry)
  end
end
