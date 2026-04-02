# frozen_string_literal: true

require 'fileutils'
require_relative 'block_parser'

module Sourcerer
  module Sync
    # Synchronizes canonical blocks from a prime template into one target file.
    #
    # See {Sourcerer::Sync} for the high-level interface and the project README
    # for usage examples and a full description of the Sync/Cast model.
    class Cast
      # Returned by both {.sync} and {.init}.
      #
      # @!attribute target_path [String] Absolute path of the target file.
      # @!attribute applied_changes [Array<String>] Tag names whose block
      #  content was replaced (empty on a dry run even when differences exist).
      # @!attribute warnings [Array<String>] Non-fatal diagnostic messages.
      # @!attribute errors [Array<String>] Fatal messages; file was not written.
      # @!attribute diff [String, nil] Unified diff output when differences were
      #  detected (populated on dry runs and when changes were applied).
      CastResult = Struct.new(
        :target_path,
        :applied_changes,
        :warnings,
        :errors,
        :diff,
        keyword_init: true)

      # Synchronize canonical blocks from `prime_path` into `target_path`.
      #
      # @param prime_path [String] Path to the prime template file
      # @param target_path [String] Path to the target file
      # @param data [Hash] Liquid variables used when rendering block content
      # @param canonical_prefix [String] Tag prefix that marks managed blocks
      # @param tag_syntax_start [String] Opening tag marker template
      #   (see {BlockParser::DEFAULT_TAG_SYNTAX_START})
      # @param tag_syntax_end [String] Closing tag marker template
      #   (see {BlockParser::DEFAULT_TAG_SYNTAX_END})
      # @param comment_syntax_patterns [Array<String>] Comment-wrapper templates
      #   (see {BlockParser::DEFAULT_COMMENT_SYNTAX_PATTERNS})
      # @param dry_run [Boolean] When true, compute the diff but do not write
      # @return [CastResult]
      def self.sync prime_path, target_path,
        data: {},
        canonical_prefix: BlockParser::DEFAULT_CANONICAL_PREFIX,
        tag_syntax_start: BlockParser::DEFAULT_TAG_SYNTAX_START,
        tag_syntax_end: BlockParser::DEFAULT_TAG_SYNTAX_END,
        comment_syntax_patterns: BlockParser::DEFAULT_COMMENT_SYNTAX_PATTERNS,
        dry_run: false
        new(
          prime_path, target_path,
          data: data,
          canonical_prefix: canonical_prefix,
          tag_syntax_start: tag_syntax_start,
          tag_syntax_end: tag_syntax_end,
          comment_syntax_patterns: comment_syntax_patterns,
          dry_run: dry_run).run_sync
      end

      # Bootstrap a new target file from the prime template.
      #
      # During init the entire prime is rendered through Liquid before writing;
      #  during sync only canonical block content is rendered.
      #  See the project README for a full description of init vs sync semantics.
      #
      # @param prime_path [String] Path to the prime template file
      # @param target_path [String] Path to the target file to create
      # @param data [Hash] Liquid variables used when rendering
      # @param dry_run [Boolean] When true, return rendered content in `diff`
      #  but do not write.
      # @return [CastResult]
      def self.init prime_path, target_path, data: {}, dry_run: false
        segments = parse_prime_segments(File.read(prime_path))

        liquid_preamble = segments
                          .find { |s| s.is_a?(BlockParser::Block) && s.tag == '_liquid' }
                          &.content.to_s

        clean_text = segments
                     .reject { |s| s.is_a?(BlockParser::Block) && s.tag.start_with?('_') }
                     .map { |s| s.is_a?(BlockParser::Block) ? "#{s.open_line}#{s.content}#{s.close_line}" : s.content }
                     .join

        rendered = if data.empty? && liquid_preamble.empty?
                     clean_text
                   else
                     # Wrap the preamble in a silent capture block so the assign statements
                     # populate variables without emitting any whitespace into the output.
                     full = if liquid_preamble.empty?
                              clean_text
                            else
                              "{%- capture __preamble__ -%}#{liquid_preamble}{%- endcapture -%}#{clean_text}"
                            end
                     render_liquid_string(full, data)
                   end

        unless dry_run
          FileUtils.mkdir_p(File.dirname(File.expand_path(target_path)))
          File.write(target_path, rendered)
        end

        CastResult.new(
          target_path: target_path,
          applied_changes: [],
          warnings: [],
          errors: [],
          diff: dry_run ? rendered : nil)
      end

      # @api private
      def initialize prime_path, target_path,
        data:, canonical_prefix:,
        tag_syntax_start:, tag_syntax_end:, comment_syntax_patterns:,
        dry_run:
        @prime_path = prime_path
        @target_path = target_path
        @data = data
        @canonical_prefix = canonical_prefix
        @tag_syntax_start = tag_syntax_start
        @dry_run = dry_run
        @tag_patterns = BlockParser.build_tag_patterns(
          tag_syntax_start, tag_syntax_end, comment_syntax_patterns)
      end

      # @api private
      def run_sync
        prime_text = File.read(@prime_path)
        target_text = File.read(@target_path)

        # Parse with canonical_prefix: '' so that ALL tagged regions -- including
        # the non-canonical _liquid preamble block -- surface as Block objects
        # rather than being swallowed into TextSegments.
        prime_segments  = BlockParser.parse(
          prime_text,
          canonical_prefix: '',
          tag_patterns: @tag_patterns)
        target_segments = BlockParser.parse(
          target_text,
          canonical_prefix: '',
          tag_patterns: @tag_patterns)

        # Extract the _liquid preamble from the prime (non-canonical; not synced as a
        # canonical block but used to carry Liquid variable context to all rendered content).
        prime_liquid_block = prime_segments.find { |s| s.is_a?(BlockParser::Block) && s.tag == '_liquid' }
        liquid_preamble = prime_liquid_block&.content.to_s

        prime_blocks = BlockParser.extract_canonical(prime_segments, canonical_prefix: @canonical_prefix)
        target_blocks, errors = validate_target_canonical(target_segments)

        if errors.any?
          return CastResult.new(
            target_path: @target_path,
            applied_changes: [],
            warnings: [],
            errors: errors,
            diff: nil)
        end

        warnings = collect_warnings(prime_blocks, target_blocks, target_text)
        new_segments, applied_changes = apply_prime_blocks(
          target_segments, prime_blocks,
          prime_liquid_block: prime_liquid_block,
          liquid_preamble: liquid_preamble)

        new_text = reconstruct(new_segments)
        diff = generate_diff(target_text, new_text) if applied_changes.any? || @dry_run

        File.write(@target_path, new_text) unless @dry_run

        CastResult.new(
          target_path: @target_path,
          applied_changes: @dry_run ? [] : applied_changes,
          warnings: warnings,
          errors: [],
          diff: diff)
      end

      # @api private
      def self.render_liquid_string content, data
        require_relative '../jekyll'
        require_relative '../jekyll/liquid/filters'
        require_relative '../jekyll/liquid/tags'
        require 'liquid' unless defined?(Liquid::Template)
        Sourcerer::Jekyll.initialize_liquid_runtime

        template = Liquid::Template.parse(content)
        template.render(data.transform_keys(&:to_s))
      end

      # Remove every underscore-prefixed meta block (+_skip+, +_liquid+, etc.) from
      # a prime text before it is written to a target during {.init}.
      # These blocks carry template instructions or Liquid context that are only
      # meaningful during the prime→target rendering pass, not in the output file.
      # @api private
      def self.strip_meta_blocks text
        parse_prime_segments(text)
          .reject { |s| s.is_a?(BlockParser::Block) && s.tag.start_with?('_') }
          .map { |s| s.is_a?(BlockParser::Block) ? "#{s.open_line}#{s.content}#{s.close_line}" : s.content }
          .join
      end

      # Parse a prime template using the default tag patterns.
      # Shared by {.init} and {.strip_meta_blocks} to avoid repeating
      # the +build_tag_patterns+ / +parse+ boilerplate.
      # @api private
      def self.parse_prime_segments text
        tag_patterns = BlockParser.build_tag_patterns(
          BlockParser::DEFAULT_TAG_SYNTAX_START,
          BlockParser::DEFAULT_TAG_SYNTAX_END,
          BlockParser::DEFAULT_COMMENT_SYNTAX_PATTERNS)
        BlockParser.parse(text, canonical_prefix: '', tag_patterns: tag_patterns)
      end

      private

      # Collect canonical blocks from target, raising errors for duplicates.
      # Returns [hash_of_canonical_blocks, errors_array].
      def validate_target_canonical target_segments
        seen = {}
        errors = []
        target_segments.each do |s|
          next unless s.is_a?(BlockParser::Block) && canonical?(s.tag)

          if seen.key?(s.tag)
            errors << "Duplicate canonical block '#{s.tag}' in target file"
          else
            seen[s.tag] = s
          end
        end
        [seen, errors]
      end

      def collect_warnings prime_blocks, target_blocks, target_text
        warnings = []

        prime_blocks.each_key do |tag|
          next if target_blocks.key?(tag)
          next if alternate_exists?(tag, target_text)

          warnings << "Prime canonical block '#{tag}' not found in target"
        end

        target_blocks.each_key do |tag|
          warnings << "Target canonical block '#{tag}' not found in prime" unless prime_blocks.key?(tag)
        end

        warnings
      end

      def apply_prime_blocks target_segments, prime_blocks,
        prime_liquid_block: nil, liquid_preamble: ''
        applied_changes = []
        has_preamble = !liquid_preamble.empty?
        liquid_seen = false

        new_segments = target_segments.map do |segment|
          if segment.is_a?(BlockParser::Block)
            if segment.tag == '_liquid'
              # Sync the _liquid block content from prime to target
              liquid_seen = true
              next segment unless prime_liquid_block
              next segment if prime_liquid_block.content == segment.content

              applied_changes << '_liquid'
              BlockParser::Block.new(
                tag: '_liquid',
                open_line: segment.open_line,
                content: prime_liquid_block.content,
                close_line: segment.close_line)

            elsif canonical?(segment.tag)
              next segment unless prime_blocks.key?(segment.tag)

              prime_content = prime_blocks[segment.tag].content
              rendered_content = render_content(prime_content, preamble: liquid_preamble)

              if rendered_content == segment.content
                segment
              else
                applied_changes << segment.tag
                BlockParser::Block.new(
                  tag: segment.tag,
                  open_line: segment.open_line,
                  content: rendered_content,
                  close_line: segment.close_line)
              end

            else
              segment
            end

          elsif segment.is_a?(BlockParser::TextSegment) && has_preamble && liquid_seen
            # Render in-between text with the preamble context, but only after the
            # _liquid block has been encountered so all variables are in scope.
            rendered_text = render_content(segment.content, preamble: liquid_preamble)
            if rendered_text == segment.content
              segment
            else
              applied_changes << 'document-text'
              BlockParser::TextSegment.new(content: rendered_text)
            end

          else
            segment
          end
        end

        [new_segments, applied_changes.uniq]
      end

      def reconstruct segments
        segments.map do |s|
          case s
          when BlockParser::Block
            "#{s.open_line}#{s.content}#{s.close_line}"
          when BlockParser::TextSegment
            s.content
          end
        end.join
      end

      def canonical? tag
        tag.start_with?(@canonical_prefix)
      end

      def alternate_exists? canonical_tag, target_text
        # Scan the raw target text for any tag marker that shares the suffix of
        #  the canonical tag but uses a different (non-canonical) prefix.
        # Ex: `local-agency` is an alternate for `universal-agency`.
        suffix     = canonical_tag.delete_prefix(@canonical_prefix)
        inner      = BlockParser.tag_template_to_inner_regex(@tag_syntax_start)
        scan_pat   = Regexp.new(inner.gsub('(?<tag>', '('))
        target_text.scan(scan_pat).flatten.any? do |found_tag|
          found_tag.end_with?(suffix) && !found_tag.start_with?(@canonical_prefix)
        end
      end

      def render_content content, preamble: ''
        return content if @data.empty? && preamble.empty?

        full = preamble.empty? ? content : "#{preamble}#{content}"
        self.class.render_liquid_string(full, @data)
      end

      def generate_diff old_text, new_text
        return nil if old_text == new_text

        require 'open3'
        require 'tempfile'

        result = nil
        Tempfile.open(['cast_old', '.txt']) do |old_f|
          old_f.write(old_text)
          old_f.flush
          Tempfile.open(['cast_new', '.txt']) do |new_f|
            new_f.write(new_text)
            new_f.flush
            stdout, = Open3.capture2('diff', '-u', old_f.path, new_f.path)
            result = stdout
          end
        end
        result
      end
    end
  end
end
