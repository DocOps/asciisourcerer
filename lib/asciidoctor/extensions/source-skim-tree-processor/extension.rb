# frozen_string_literal: true

require 'asciidoctor/extensions'
require_relative '../../../sourcerer/source_skim'

module Sourcerer
  module SourceSkim
    # Asciidoctor TreeProcessor extension that runs a SourceSkim pass on the
    # document immediately after parsing and stores the result as the document
    # attribute +source-skim-result+.
    #
    # The skim is keyed by symbol (+:title+, +:sections_tree+, etc.) so it is
    # ready for direct use in Ruby without a JSON round-trip.
    #
    # == Configuration via document attributes
    #
    # +source-skim-forms+:: Comma-separated list of section shapes to emit.
    #   Recognized values: +tree+, +flat+. Default: +tree+.
    # +source-skim-categories+:: Comma-separated list of element categories to
    #   include. Omit to use the default set (everything except
    #   +attributes_builtin+).
    #
    # == Usage
    #
    # === API
    #
    # require 'asciidoctor/extensions/source-skim-tree-processor/extension'
    #
    # Asciidoctor::Extensions.register Sourcerer::SourceSkim::TreeProcessorExtension
    #
    #   doc  = Asciidoctor.load_file('my.adoc', safe: :safe, sourcemap: true)
    #   skim = doc.attr('source-skim-result')
    #
    # === With asciidoctor CLI
    #
    #  asciidoctor -r ./lib/asciidoctor/extensions/source-skim-tree-processor/extension.rb \
    #     -a source-skim-forms=tree,flat \
    #     -a source-skim-categories=sections,code_blocks,admonitions \
    #     my.adoc
    class TreeProcessorExtension < Asciidoctor::Extensions::TreeProcessor
      def process document
        raw_forms = document.attr('source-skim-forms', 'tree')
        forms     = raw_forms.split(',').map { |f| f.strip.to_sym }

        raw_cats   = document.attr('source-skim-categories')
        categories = raw_cats&.split(',')&.map { |c| c.strip.to_sym }

        config = Config.new(forms: forms, categories: categories)
        skim   = Skimmer.new.process(document, config: config)
        document.set_attr('source-skim-result', skim)
        nil
      end
    end
  end
end
