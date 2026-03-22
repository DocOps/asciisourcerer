# frozen_string_literal: true

module Sourcerer
  module SourceSkim
    # All recognized element categories. Sections are shape-controlled via +forms+
    # rather than listed here.
    ALL_CATEGORIES = %i[
      attributes_custom
      attributes_builtin
      definition_lists
      code_blocks
      literal_blocks
      examples
      sidebars
      tables
      admonitions
      quotes
      images
    ].freeze

    # Categories included when a caller passes +categories: nil+ (the default).
    # +attributes_builtin+, +admonitions+, and +quotes+ are opt-in only.
    DEFAULT_CATEGORIES = (ALL_CATEGORIES - %i[attributes_builtin admonitions quotes]).freeze

    # Configuration profile for a single SourceSkim pass.
    #
    # Controls which section shapes and element categories are emitted.
    # Callers pass a +Config+ instance to {Skimmer#process}; it is not part of
    # the public-facing module API and should be constructed via the keyword
    # arguments on {Sourcerer::SourceSkim.skim_file} and friends.
    # @api private
    class Config
      attr_reader :forms, :categories

      def initialize forms: [:tree], categories: nil
        @forms = Array(forms).map(&:to_sym)
        @categories = categories ? Array(categories).map(&:to_sym) : DEFAULT_CATEGORIES.dup
      end

      def include? category
        @categories.include?(category.to_sym)
      end

      def tree?
        @forms.include?(:tree)
      end

      def flat?
        @forms.include?(:flat)
      end
    end
  end
end
