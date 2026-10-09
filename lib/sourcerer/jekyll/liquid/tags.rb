# frozen_string_literal: true

module Sourcerer
  module Jekyll
    module Liquid
      # This module contains custom Liquid tags for the Sourcerer templating environment.
      module Tags
        # A Liquid tag for embedding and rendering a file within a template.
        # It searches for the file in the configured include paths.
        class EmbedTag < ::Liquid::Tag
          # Matches an optional single- or double-quoted string, capturing the
          # inner content; falls back to the whole (trimmed) markup as a bareword.
          # Requires at least one character inside the quotes: an empty quoted
          # name (`""`/`''`) would otherwise expand to the includes directory
          # itself, pass File.exist?, and raise Errno::EISDIR from File.read
          # instead of the intended missing-file error. Left unmatched, it
          # falls through to the bareword branch instead, where the literal
          # (quoted) name is looked up and not found -- reported normally.
          PARTIAL_NAME_PATTERN = /\A(?:"([^"]+)"|'([^']+)')\z/

          # @param tag_name [String] The name of the tag ('embed').
          # @param markup [String] The name of the partial to embed, quoted
          #   (+"foo.liquid"+ / +'foo.liquid'+) or bareword (+foo.liquid+).
          # @param tokens [Array<String>] The list of tokens.
          def initialize tag_name, markup, tokens
            super
            trimmed = markup.strip
            match = trimmed.match(PARTIAL_NAME_PATTERN)
            @partial_name = match ? (match[1] || match[2]) : trimmed
          end

          # Renders the embedded file.
          #
          # @param context [Liquid::Context] The Liquid context.
          # @return [String] The rendered content of the embedded file.
          # @raise [IOError] if the embed file is not found.
          def render context
            includes_paths = context.registers[:includes_load_paths]
            includes_paths = site_includes_load_paths(context) if includes_paths.nil? || includes_paths.empty?
            includes_paths ||= []

            found_path = includes_paths.find do |base|
              candidate = File.expand_path(@partial_name, base)
              File.exist?(candidate)
            end

            raise "Embed file not found: #{@partial_name}" unless found_path

            full_path = File.expand_path(@partial_name, found_path)
            source = File.read(full_path)

            partial = ::Liquid::Template.parse(source)
            partial.render!(context)
          end

          private

          # Fallback for callers that register a fake/real Jekyll +:site+ but
          # forget the separate +:includes_load_paths+ register (e.g. any
          # future caller mirroring {Sourcerer::Rendering.render_liquid}).
          # Reads +site.config['includes_load_paths']+ directly rather than
          # +site.includes_load_paths+: the latter is Jekyll's own attribute,
          # derived only from +config['includes_dir']+ (effectively just the
          # first path), not the full list Sourcerer stores in config.
          def site_includes_load_paths context
            context.registers[:site]&.config&.[]('includes_load_paths')
          end
        end
      end
    end
  end
end
