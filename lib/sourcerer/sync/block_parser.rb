# frozen_string_literal: true

module Sourcerer
  module Sync
    # Parses tagged regions from any text file, regardless of comment style
    #
    # Recognizes AsciiDoc `tag::`/`end::` markers in HTML comments, AsciiDoc line comments,
    #  and shell/Ruby/YAML comments.
    # The trailing `[]` is optional.
    # See the project README for the full tag-syntax reference.
    module BlockParser
      # A tagged region extracted from a file
      #
      # @!attribute tag [String] The tag name (e.g. `universal-agency`)
      # @!attribute open_line [String] The complete opening marker line, including newline
      # @!attribute content [String] Everything between the open and close markers
      # @!attribute close_line [String] The complete closing marker line, including newline
      Block = Struct.new(:tag, :open_line, :content, :close_line, keyword_init: true)

      # Plain text in between (or around) tagged blocks
      #
      # @!attribute content [String] The raw text
      TextSegment = Struct.new(:content, keyword_init: true)

      # Raised when tag markers are structurally invalid
      class ParseError < StandardError
      end

      # Default prefix that marks a block as canonical (managed by Sync/Cast).
      DEFAULT_CANONICAL_PREFIX = 'universal-'

      # Default opening tag marker template.
      # `<tagged_block_name>` is the placeholder for the block name character class.
      # A trailing `[]` is treated as optional in the compiled pattern.
      DEFAULT_TAG_SYNTAX_START = 'tag::<tagged_block_name>[]'

      # Default closing tag marker template.
      DEFAULT_TAG_SYNTAX_END = 'end::<tagged_block_name>[]'

      # Default comment-wrapper templates.
      # `<tag_syntax>` is the placeholder for the compiled tag marker pattern.
      # A space between the comment delimiter and `<tag_syntax>` compiles as `\s*`.
      DEFAULT_COMMENT_SYNTAX_PATTERNS = [
        '<!-- <tag_syntax> -->',
        '// <tag_syntax>',
        '# <tag_syntax>'
      ].freeze

      # Compile a tag marker template string into a plain regex fragment (no `\A` anchor).
      #
      # `<tagged_block_name>` is replaced with the `(?<tag>[\w-]+)` named capture group.
      # A trailing `[]` in the template becomes `(?:\[\])?` (optional literal brackets).
      #
      # @param template [String] e.g. `'tag::<tagged_block_name>[]'`
      # @return [String] regex source string
      def self.tag_template_to_inner_regex template
        parts  = template.split('<tagged_block_name>', 2)
        left   = Regexp.escape(parts[0])
        right  = parts[1].to_s
        suffix = right == '[]' ? '(?:\[\])?' : Regexp.escape(right)
        "#{left}(?<tag>[\\w-]+)#{suffix}"
      end

      # Wrap a compiled inner-tag regex fragment with a comment-wrapper template.
      #
      # `<tag_syntax>` in `comment_template` is replaced by `inner_regex`.
      # Adjacent literal spaces around `<tag_syntax>` are compiled as `\s*`.
      # The result is anchored to `\A`.
      #
      # @param comment_template [String] e.g. `'<!-- <tag_syntax> -->'`
      # @param inner_regex [String] regex source from {.tag_template_to_inner_regex}
      # @return [String] full anchored regex source string
      def self.comment_template_to_full_regex comment_template, inner_regex
        halves    = comment_template.split('<tag_syntax>', 2)
        left_raw  = halves[0]
        right_raw = halves[1].to_s
        left_trim  = left_raw.rstrip
        right_trim = right_raw.lstrip
        left_re  = Regexp.escape(left_trim) + (left_trim == left_raw ? '' : '\s*')
        right_re = (right_trim == right_raw ? '' : '\s*') + Regexp.escape(right_trim)
        "\\A#{left_re}#{inner_regex}#{right_re}"
      end

      # Compile template strings into a patterns array compatible with {.parse}.
      #
      # Each entry in the returned array is a `{open: Regexp, close: Regexp}` hash.
      # This is the same shape as {DEFAULT_TAG_PATTERNS} and may be passed directly
      # to {.parse} via the `tag_patterns:` keyword to avoid recompilation per call.
      #
      # @param tag_start [String] opening tag template (default {DEFAULT_TAG_SYNTAX_START})
      # @param tag_end [String] closing tag template (default {DEFAULT_TAG_SYNTAX_END})
      # @param comment_patterns [Array<String>] comment-wrapper templates
      #   (default {DEFAULT_COMMENT_SYNTAX_PATTERNS})
      # @return [Array<Hash>]
      def self.build_tag_patterns tag_start, tag_end, comment_patterns
        open_inner  = tag_template_to_inner_regex(tag_start)
        close_inner = tag_template_to_inner_regex(tag_end)
        comment_patterns.map do |cp|
          {
            open:  Regexp.new(comment_template_to_full_regex(cp, open_inner)),
            close: Regexp.new(comment_template_to_full_regex(cp, close_inner))
          }
        end
      end

      # Default compiled pattern set, built from the three DEFAULT_* template constants.
      # Retained for backward compatibility; prefer the template constants for customisation.
      DEFAULT_TAG_PATTERNS = build_tag_patterns(
        DEFAULT_TAG_SYNTAX_START,
        DEFAULT_TAG_SYNTAX_END,
        DEFAULT_COMMENT_SYNTAX_PATTERNS).freeze

      # Backward-compatible alias for {DEFAULT_TAG_PATTERNS}.
      TAG_PATTERNS = DEFAULT_TAG_PATTERNS

      # Parse a text string into an array of {TextSegment} and {Block} objects.
      #
      # The result is ordered and reconstructable: joining every element's
      #  serialized form reproduces the original text character-perfectly.
      #
      # Only blocks whose tag name starts with `canonical_prefix` are parsed as
      #  proper {Block} objects; all other tag markers (open and close) are
      #  treated as ordinary text.
      # This makes the parser robust against files that use tag markers for unrelated
      #  purposes (e.g. AsciiDoc `include::` target regions or non-canonical project sections)
      #  regardless of whether those regions are properly closed or even nested.
      #
      # When a canonical block is open, every line is treated as content until
      #  the matching close marker appears (including any inner tag markers).
      # Canonical blocks therefore cannot be nested.
      #
      # @param text [String] Full text of the file to parse
      # @param canonical_prefix [String] Only tags starting with this prefix
      #   are parsed as managed {Block} objects (default {DEFAULT_CANONICAL_PREFIX}).
      # @param tag_syntax_start [String] Opening tag template; used to build
      #   patterns when `tag_patterns:` is not given (default {DEFAULT_TAG_SYNTAX_START}).
      # @param tag_syntax_end [String] Closing tag template (default {DEFAULT_TAG_SYNTAX_END}).
      # @param comment_syntax_patterns [Array<String>] Comment-wrapper templates
      #   (default {DEFAULT_COMMENT_SYNTAX_PATTERNS}).
      # @param tag_patterns [Array<Hash>, nil] Pre-compiled pattern set; skips template
      #   compilation when provided. Build once with {.build_tag_patterns} and reuse.
      # @return [Array<TextSegment, Block>]
      # @raise [ParseError] if a canonical tag is opened but never closed.
      def self.parse text,
        canonical_prefix: DEFAULT_CANONICAL_PREFIX,
        tag_syntax_start: DEFAULT_TAG_SYNTAX_START,
        tag_syntax_end: DEFAULT_TAG_SYNTAX_END,
        comment_syntax_patterns: DEFAULT_COMMENT_SYNTAX_PATTERNS,
        tag_patterns: nil
        patterns = tag_patterns ||
                   build_tag_patterns(tag_syntax_start, tag_syntax_end, comment_syntax_patterns)
        lines = text.lines
        segments = []
        text_acc = []
        block_state = nil # nil or { tag:, open_line:, content_lines: [] }

        lines.each do |line|
          stripped = line.chomp

          if block_state.nil?
            tag = detect_open_tag(stripped, patterns)
            if tag&.start_with?(canonical_prefix)
              segments << TextSegment.new(content: text_acc.join) unless text_acc.empty?
              text_acc = []
              block_state = { tag: tag, open_line: line, content_lines: [] }
            else
              # Non-canonical open tags and all close tags at the top level are
              # treated as ordinary text.
              text_acc << line
            end
          else
            close_tag = detect_close_tag(stripped, patterns)
            if close_tag == block_state[:tag]
              segments << Block.new(
                tag: block_state[:tag],
                open_line: block_state[:open_line],
                content: block_state[:content_lines].join,
                close_line: line)
              block_state = nil
            else
              # Nested open tags or mismatched close tags: treat as block content
              block_state[:content_lines] << line
            end
          end
        end

        raise ParseError, "Unclosed canonical tag '#{block_state[:tag]}'" if block_state

        segments << TextSegment.new(content: text_acc.join) unless text_acc.empty?
        segments
      end

      # Return the tag name if `stripped_line` is an opening tag marker, else nil.
      #
      # @param stripped_line [String] A single line with the trailing newline removed
      # @param patterns [Array<Hash>] compiled pattern set from {.build_tag_patterns}
      # @return [String, nil]
      def self.detect_open_tag stripped_line, patterns
        patterns.each do |p|
          m = stripped_line.match(p[:open])
          return m[:tag] if m
        end
        nil
      end

      # Return the tag name if `stripped_line` is a closing tag marker, else nil.
      #
      # @param stripped_line [String] A single line with the trailing newline removed
      # @param patterns [Array<Hash>] compiled pattern set from {.build_tag_patterns}
      # @return [String, nil]
      def self.detect_close_tag stripped_line, patterns
        patterns.each do |p|
          m = stripped_line.match(p[:close])
          return m[:tag] if m
        end
        nil
      end

      # Extract all canonical blocks (those whose tag name starts with
      #  `canonical_prefix`) as a Hash keyed by tag name.
      #
      # Because {.parse} already filters for canonical blocks when given the
      #  same `canonical_prefix`, this method is largely a deduplication check.
      # It raises {ParseError} if more than one canonical block carries the same
      #  tag name, which would make synchronization ambiguous.
      #
      # @param segments [Array<TextSegment, Block>]
      # @param canonical_prefix [String] Prefix that identifies managed blocks
      # @return [Hash{String => Block}]
      def self.extract_canonical segments, canonical_prefix: DEFAULT_CANONICAL_PREFIX
        result = {}
        segments.each do |s|
          next unless s.is_a?(Block) && s.tag.start_with?(canonical_prefix)

          raise ParseError, "Duplicate canonical block '#{s.tag}'" if result.key?(s.tag)

          result[s.tag] = s
        end
        result
      end

      private_class_method :detect_open_tag, :detect_close_tag
    end
  end
end
