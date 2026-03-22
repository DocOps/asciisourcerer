# frozen_string_literal: true

require 'asciidoctor'

module Sourcerer
  # Utilities for filtering and partitioning Asciidoctor document attributes.
  #
  # The primary use case is separating user-defined ("custom") attributes from
  # those injected by Asciidoctor at parse time ("built-in"). This distinction
  # matters when a skim consumer needs to inspect only the attributes an author
  # explicitly set in their source.
  #
  # Additional attribute manipulation helpers may be added here over time.
  #
  # @example
  #   custom = Sourcerer::AttributesFilter.user_attributes(doc)
  #   builtin = Sourcerer::AttributesFilter.builtin_attributes(doc)
  module AttributesFilter
    # Attribute keys injected by Asciidoctor at parse time rather than defined
    # by the document author.
    BUILTIN_ATTR_KEYS = (Asciidoctor::DEFAULT_ATTRIBUTES.keys + %w[
      asciidoctor asciidoctor-version
      attribute-missing attribute-undefined
      authorcount
      docdate docdatetime docdir docfile docfilesuffix docname doctime doctitle doctype docyear
      embedded
      htmlsyntax
      iconsdir
      localdate localdatetime localtime localyear
      max-include-depth
      notitle
      outfilesuffix
      stylesdir
      toc-position
      user-home
    ]).freeze

    BUILTIN_ATTR_PATTERNS = [
      /^backend(-|$)/,
      /^basebackend(-|$)/,
      /^doctype-/,
      /^filetype(-|$)/,
      /^safe-mode-/
    ].freeze

    module_function

    # Returns a hash of user-defined attributes, excluding any key that belongs
    # to Asciidoctor's built-in set.
    #
    # @param doc [Asciidoctor::Document]
    # @return [Hash{String => String}]
    def user_attributes doc
      doc.attributes.reject do |k, _|
        BUILTIN_ATTR_KEYS.include?(k) ||
          BUILTIN_ATTR_PATTERNS.any? { |pat| pat.match?(k) }
      end
    end

    # Returns a hash of built-in Asciidoctor attributes, i.e., those injected at
    # parse time rather than authored in the document.
    #
    # @param doc [Asciidoctor::Document]
    # @return [Hash{String => String}]
    def builtin_attributes doc
      doc.attributes.select do |k, _|
        BUILTIN_ATTR_KEYS.include?(k) ||
          BUILTIN_ATTR_PATTERNS.any? { |pat| pat.match?(k) }
      end
    end
  end
end
