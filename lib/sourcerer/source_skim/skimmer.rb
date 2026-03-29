# frozen_string_literal: true

module Sourcerer
  module SourceSkim
    # Traverses a parsed Asciidoctor document and produces a JSON-ready skim hash.
    #
    # A new instance should be created per-document call; instance variables
    # accumulate state during a single +process+ pass.
    #
    # This class is an internal implementation detail. External callers should
    # use the {Sourcerer::SourceSkim} module-level methods rather than
    # instantiating +Skimmer+ directly.
    # @api private
    class Skimmer
      # Scan listing/literal block source for include directives that remain as
      # raw text (i.e., were not resolved by the parser).
      INCLUDE_DIRECTIVE_PATTERN = /include::[^\[]+\[[^\]]*\]/

      def process document, config: Config.new
        @config = config
        @main_file = document.attr('docfile')
        @definition_lists = []
        @code_blocks       = []
        @literal_blocks    = []
        @examples          = []
        @sidebars          = []
        @tables            = []
        @admonitions       = []
        @quotes            = []
        @images            = []

        process_blocks(document.blocks, 0, nil)

        tree    = build_sections_tree(document.sections)
        doc_end = line_count_for(@main_file)
        assign_line_ends(tree, doc_end)

        result = {
          title: document.doctitle,
          lines: doc_end
        }

        if @config.include?(:attributes_custom)
          result[:attributes_custom] =
            Sourcerer::AsciiDoc::AttributesFilter.user_attributes(document)
        end
        if @config.include?(:attributes_builtin)
          result[:attributes_builtin] =
            Sourcerer::AsciiDoc::AttributesFilter.builtin_attributes(document)
        end

        result[:sections_tree] = tree if @config.tree?
        result[:sections_flat] = flatten_sections(tree) if @config.flat?

        result[:definition_lists] = @definition_lists if @config.include?(:definition_lists)
        result[:code_blocks]      = @code_blocks       if @config.include?(:code_blocks)
        result[:literal_blocks]   = @literal_blocks    if @config.include?(:literal_blocks)
        result[:examples]         = @examples          if @config.include?(:examples)
        result[:sidebars]         = @sidebars          if @config.include?(:sidebars)
        result[:tables]           = @tables            if @config.include?(:tables)
        result[:admonitions]      = @admonitions       if @config.include?(:admonitions)
        result[:quotes]           = @quotes            if @config.include?(:quotes)
        result[:images]           = @images            if @config.include?(:images)

        result
      end

      private

      def line_count_for file_path
        return nil unless file_path && File.exist?(file_path)

        File.foreach(file_path).inject(0) { |c, _| c + 1 }
      end

      # Returns the relative filename when +loc+ originates from an included file,
      # nil otherwise (meaning the block came from the main document).
      def file_for loc
        return nil unless loc

        f = loc.file
        return nil unless f
        return nil if @main_file && f == @main_file

        loc.path || File.basename(f)
      end

      def build_sections_tree sections, level = 0
        sections.map do |section|
          loc = section.source_location
          f   = file_for(loc)
          record = {}
          record[:file] = f if f
          record.merge!(
            id:        section.id,
            text:      section.title,
            level:     level + 1,
            starts_at: loc&.lineno,
            sections:  build_sections_tree(section.sections, level + 1))
          record
        end
      end

      # Assigns +ends_near+ to each section in-place. +parent_end_line+ is the
      # last line of the enclosing scope (document total or parent section end).
      def assign_line_ends sections, parent_end_line
        sections.each_with_index do |rec, i|
          next_start = sections[i + 1]&.dig(:starts_at)
          end_line   = next_start ? next_start - 1 : parent_end_line
          # Omit ends_near from include-sourced nodes: their starts_at is a line
          # number in the included file, so mixing it with a main-file end bound
          # would produce a misleading range.
          rec[:ends_near] = end_line unless rec.key?(:file)
          assign_line_ends(rec[:sections], end_line)
        end
      end

      # Returns a pre-order flat array from the annotated tree. Each record
      # carries +parent_id+ (nil for root) and +sections+ as an array of child IDs.
      def flatten_sections sections, acc = [], parent_id = nil
        sections.each do |rec|
          children  = rec[:sections]
          flat_rec  = rec.except(:sections)
          flat_rec[:parent_id] = parent_id
          flat_rec[:sections]  = children.map { |c| c[:id] }
          acc << flat_rec
          flatten_sections(children, acc, rec[:id])
        end
        acc
      end

      def detect_includes source
        return [] unless source

        source.scan(INCLUDE_DIRECTIVE_PATTERN)
      end

      def process_blocks blocks, level, section_id
        # rubocop:disable Metrics/BlockLength
        blocks.each do |block|
          case block.context
          when :section
            process_blocks(block.blocks, level + 1, block.id)

          when :dlist
            next unless @config.include?(:definition_lists)

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file]  = f if f
            entry[:title] = block.title
            entry[:role]  = block.style if block.style && !block.style.empty?
            entry.merge!(
              starts_at:        loc&.lineno,
              section_id:       section_id,
              definition_terms: block.items.flat_map do |terms, _|
                terms.map do |term|
                  tloc = term.source_location
                  { text: term.text, starts_at: tloc&.lineno }
                end
              end)
            @definition_lists << entry

          when :listing
            next unless @config.include?(:code_blocks)
            next unless block.title

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file] = f if f
            entry.merge!(title: block.title, starts_at: loc&.lineno)
            entry[:language]   = block.attr('language') if block.style == 'source'
            entry[:section_id] = section_id
            entry[:includes]   = detect_includes(block.source)
            @code_blocks << entry

          when :literal
            next unless @config.include?(:literal_blocks)
            next unless block.title

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file] = f if f
            entry.merge!(
              title:      block.title,
              starts_at:  loc&.lineno,
              section_id: section_id,
              includes:   detect_includes(block.source))
            @literal_blocks << entry

          when :example
            next unless @config.include?(:examples)
            next unless block.title

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file] = f if f
            entry.merge!(
              title:      block.title,
              starts_at:  loc&.lineno,
              section_id: section_id,
              includes:   [])
            @examples << entry
            process_blocks(block.blocks, level, section_id) if block.blocks.any?

          when :sidebar
            next unless @config.include?(:sidebars)
            next unless block.title

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file] = f if f
            entry.merge!(
              title:      block.title,
              starts_at:  loc&.lineno,
              section_id: section_id,
              includes:   [])
            @sidebars << entry
            process_blocks(block.blocks, level, section_id) if block.blocks.any?

          when :table
            next unless @config.include?(:tables)

            header_row = block.rows.head.first
            headers    = header_row&.map(&:text) if header_row && !header_row.empty?
            next unless block.title || headers

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file]    = f if f
            entry[:title]   = block.title
            entry[:headers] = headers if headers
            entry.merge!(starts_at: loc&.lineno, section_id: section_id)
            @tables << entry

          when :admonition
            next unless @config.include?(:admonitions)
            next unless block.title

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file] = f if f
            entry.merge!(
              type:       block.style,
              title:      block.title,
              starts_at:  loc&.lineno,
              section_id: section_id)
            @admonitions << entry
            process_blocks(block.blocks, level, section_id) if block.respond_to?(:blocks) && block.blocks.any?

          when :quote, :verse
            next unless @config.include?(:quotes)

            attribution = block.attr('attribution')
            next unless block.title || attribution

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file]        = f if f
            entry[:title]       = block.title
            entry[:attribution] = attribution if attribution
            entry.merge!(starts_at: loc&.lineno, section_id: section_id)
            @quotes << entry

          when :image
            next unless @config.include?(:images)

            loc   = block.source_location
            f     = file_for(loc)
            entry = { id: block.id }
            entry[:file]  = f if f
            entry[:title] = block.title if block.title
            entry.merge!(
              target:     block.attr('target'),
              alt:        block.attr('alt'),
              starts_at:  loc&.lineno,
              section_id: section_id)
            entry[:width]  = block.attr('width') if block.attr('width')
            entry[:height] = block.attr('height') if block.attr('height')
            @images << entry

          else
            process_blocks(block.blocks, level, section_id) if block.respond_to?(:blocks) && block.blocks.any?
          end
        end
        # rubocop:enable Metrics/BlockLength
      end
    end
  end
end
