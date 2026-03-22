# frozen_string_literal: true

require 'asciidoctor'
require 'logger'
require_relative 'attributes_filter'
require_relative 'source_skim/config'
require_relative 'source_skim/skimmer'

module Sourcerer
  # SourceSkim produces machine-oriented skims of AsciiDoc source documents.
  #
  # A skim is a structured, JSON-ready representation of selected source elements
  # intended to help automated tooling inspect documentation source and identify
  # likely areas of interest when related product code changes.
  #
  # @example Skim a file with default tree output
  #   skim = Sourcerer::SourceSkim.skim_file('docs/install.adoc')
  #
  # @example Skim with both tree and flat section shapes
  #   skim = Sourcerer::SourceSkim.skim_file('docs/install.adoc', forms: [:tree, :flat])
  #
  # @example Skim a content string
  #   skim = Sourcerer::SourceSkim.skim_string(adoc_content, forms: [:flat])
  #
  # @example Skim with caller-supplied attribute overrides
  #   skim = Sourcerer::SourceSkim.skim_file('docs/ref.adoc', attributes: { 'env' => 'prod' })
  module SourceSkim
    NULL_LOGGER = Logger.new(IO::NULL)
    LOAD_OPTS   = { safe: :safe, sourcemap: true, logger: NULL_LOGGER }.freeze

    # Skim the AsciiDoc file at +file_path+.
    #
    # @param file_path [String] path to the .adoc source file
    # @param forms [Array<Symbol>] section shape(s) to emit: +:tree+, +:flat+, or both
    # @param categories [Array<Symbol>, nil] element categories to include;
    #   nil uses {DEFAULT_CATEGORIES} (everything except +attributes_builtin+)
    # @param attributes [Hash{String => String}] arbitrary Asciidoctor attribute
    #   overrides applied at parse time, e.g. <tt>'env' => 'test'</tt>.
    #   Useful for toggling conditionals or injecting values that affect which
    #   blocks are visible to the parser.
    # @return [Hash] JSON-ready skim
    def self.skim_file file_path, forms: [:tree], categories: nil, attributes: {}
      opts = LOAD_OPTS.merge(attributes: attributes)
      doc  = Asciidoctor.load_file(file_path, **opts)
      skim_doc(doc, forms: forms, categories: categories)
    end

    # Skim AsciiDoc source from a +content+ string.
    #
    # @param content [String] raw AsciiDoc markup
    # @param forms [Array<Symbol>] section shape(s) to emit
    # @param categories [Array<Symbol>, nil] element categories to include
    # @param attributes [Hash{String => String}] arbitrary Asciidoctor attribute
    #   overrides applied at parse time
    # @return [Hash] JSON-ready skim
    def self.skim_string content, forms: [:tree], categories: nil, attributes: {}
      opts = LOAD_OPTS.merge(attributes: attributes)
      doc  = Asciidoctor.load(content, **opts)
      skim_doc(doc, forms: forms, categories: categories)
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
  end
end
