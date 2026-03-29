# frozen_string_literal: true

require 'asciidoctor'
require 'logger'
require_relative 'yaml_frontmatter'
require_relative 'source_skim/config'
require_relative 'source_skim/skimmer'
require_relative 'source_skim/markdown_skimmer'

module Sourcerer
  # SourceSkim produces machine-oriented skims of markup source documents.
  #
  # A skim is a structured, JSON-ready representation of selected source elements
  # intended to help automated tooling inspect documentation source and identify
  # likely areas of interest when related product code changes.
  #
  # AsciiDoc files are fully parsed by Asciidoctor and yield rich semantic
  # output (sections, attributes, code blocks, tables, etc.). Markdown files
  # yield frontmatter and section headings only, since Markdown has no
  # standardised semantic block model.
  #
  # The format is auto-detected from the file extension when using +skim_file+.
  # Pass +format: :markdown+ or +format: :asciidoc+ to +skim_string+ to
  # disambiguate when there is no path to inspect.
  #
  # @example Skim an AsciiDoc file (auto-detected)
  #   skim = Sourcerer::SourceSkim.skim_file('docs/install.adoc')
  #
  # @example Skim a Markdown file (auto-detected)
  #   skim = Sourcerer::SourceSkim.skim_file('docs/guide.md')
  #
  # @example Skim with both tree and flat section shapes
  #   skim = Sourcerer::SourceSkim.skim_file('docs/install.adoc', forms: [:tree, :flat])
  #
  # @example Skim a Markdown string explicitly
  #   skim = Sourcerer::SourceSkim.skim_string(content, format: :markdown)
  #
  # @example Skim with caller-supplied Asciidoctor attribute overrides
  #   skim = Sourcerer::SourceSkim.skim_file('docs/ref.adoc', attributes: { 'env' => 'prod' })
  module SourceSkim
    NULL_LOGGER       = Logger.new(IO::NULL)
    LOAD_OPTS         = { safe: :safe, sourcemap: true, logger: NULL_LOGGER,
                          attributes: { 'skip-front-matter' => '' } }.freeze

    # Skim the markup file at +file_path+.
    #
    # Format is auto-detected from the file extension (.adoc → AsciiDoc;
    # .md / .markdown → Markdown). Override with +format: :asciidoc+ or
    # +format: :markdown+.
    #
    # @param file_path [String] path to the source file
    # @param forms [Array<Symbol>, nil] section shape(s) to emit: +:tree+, +:flat+,
    #   or both. Defaults to +[:tree]+ for AsciiDoc and +[:flat]+ for Markdown.
    # @param format [Symbol, nil] +:asciidoc+ or +:markdown+; nil auto-detects
    # @param categories [Array<Symbol>, nil] AsciiDoc only. Element categories to
    #   include; nil uses {DEFAULT_CATEGORIES}. Silently ignored for Markdown.
    # @param attributes [Hash{String => String}] AsciiDoc only. Asciidoctor
    #   attribute overrides. Silently ignored for Markdown.
    # @return [Hash] JSON-ready skim
    def self.skim_file file_path, forms: nil, format: nil, categories: nil, attributes: {}
      fmt = format || detect_format(file_path)
      if fmt == :markdown
        config = Config.new(forms: forms || [:flat])
        MarkdownSkimmer.new.process(File.read(file_path), config: config)
      else
        attrs = LOAD_OPTS[:attributes].merge(attributes)
        opts  = LOAD_OPTS.merge(attributes: attrs)
        doc   = Asciidoctor.load_file(file_path, **opts)
        skim_doc(doc, forms: forms || [:tree], categories: categories)
      end
    end

    # Skim markup source from a +content+ string.
    #
    # +format:+ must be provided when the content is Markdown, since there is
    # no file extension to inspect. Defaults to +:asciidoc+ for backward
    # compatibility.
    #
    # @param content [String] raw markup text
    # @param format [Symbol] +:asciidoc+ (default) or +:markdown+
    # @param forms [Array<Symbol>, nil] section shape(s) to emit
    # @param categories [Array<Symbol>, nil] AsciiDoc only
    # @param attributes [Hash{String => String}] AsciiDoc only
    # @return [Hash] JSON-ready skim
    def self.skim_string content, format: :asciidoc, forms: nil, categories: nil, attributes: {}
      if format == :markdown
        config = Config.new(forms: forms || [:flat])
        MarkdownSkimmer.new.process(content, config: config)
      else
        attrs = LOAD_OPTS[:attributes].merge(attributes)
        opts  = LOAD_OPTS.merge(attributes: attrs)
        doc   = Asciidoctor.load(content, **opts)
        skim_doc(doc, forms: forms || [:tree], categories: categories)
      end
    end

    # Skim an already-parsed Asciidoctor +document+.
    #
    # This entry point is useful when the document has been loaded through
    # other means, such as from an Asciidoctor extension callback.
    #
    # @param doc [Asciidoctor::Document] parsed document object
    # @param forms [Array<Symbol>] section shape(s) to emit
    # @param categories [Array<Symbol>, nil] element categories to include
    # @return [Hash] JSON-ready skim
    def self.skim_doc doc, forms: [:tree], categories: nil
      config = Config.new(forms: forms, categories: categories)
      Skimmer.new.process(doc, config: config)
    end

    # @api private
    def self.detect_format file_path
      ext = File.extname(file_path).downcase
      if Sourcerer::MARKDOWN_EXTS.include?(ext)
        :markdown
      else
        :asciidoc
      end
    end
    private_class_method :detect_format
  end
end
