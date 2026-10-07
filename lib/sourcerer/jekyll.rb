# frozen_string_literal: true

require_relative 'jekyll/bootstrapper'
require_relative 'jekyll/monkeypatches'
require_relative 'jekyll/liquid/file_system'
require_relative 'jekyll/liquid/filters'
require_relative 'jekyll/liquid/tags'
require_relative 'jekyll/liquid/preserve_missing_variables'
require 'jekyll-asciidoc'

module Sourcerer
  # This module encapsulates the logic for initializing a Jekyll-like Liquid
  # templating environment. It loads necessary plugins, applies monkeypatches,
  # and registers custom Liquid filters and tags.
  module Jekyll
    # Initializes the Liquid templating runtime by loading plugins,
    # applying patches, and registering custom filters.
    def self.initialize_liquid_runtime
      Bootstrapper.load_plugins
      Monkeypatches.patch_jekyll

      # Registration order matters: Liquid's Strainer `include`s each module in
      # turn, so a later registration wins over an earlier one for any
      # same-named filter method. Sourcerer's filters register LAST so that,
      # e.g., its `inspect` (which adds a `format` argument) overrides
      # Jekyll's `inspect` rather than being shadowed by it.
      # Ensure Jekyll filters are registered
      ::Liquid::Template.register_filter(::Jekyll::Filters)
      # Ensure jekyll-asciidoc filters are registered
      ::Liquid::Template.register_filter(::Jekyll::AsciiDoc::Filters)
      # Ensure Sourcerer filters are registered (last, so they can override)
      ::Liquid::Template.register_filter(::Sourcerer::Jekyll::Liquid::Filters)
      # Ensure Sourcerer tags are registered
      ::Liquid::Template.register_tag('embed', ::Sourcerer::Jekyll::Liquid::Tags::EmbedTag)
    end
  end
end
