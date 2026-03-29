# frozen_string_literal: true

module Sourcerer
  module SourceSkim
    # Parses Markdown content and produces a JSON-ready skim hash.
    #
    # Heading levels are mapped to mirror AsciiDoc document structure:
    # a single +#+ heading becomes the document title (level 0); all subsequent
    # +#++#+ headings become sections starting at level 1. This keeps Markdown
    # and AsciiDoc skim output shapes consistent.
    #
    # A new instance should be created per-document call. External callers should
    # use {Sourcerer::SourceSkim.skim_file} or {Sourcerer::SourceSkim.skim_string}
    # with a Markdown file or +format: :markdown+ rather than instantiating this
    # class directly.
    # @api private
    class MarkdownSkimmer
      # Matches ATX-style Markdown headings: one to six leading # characters.
      MD_HEADING_RE = /^(\#{1,6})\s+(.+?)\s*$/

      # @param content [String] raw Markdown text
      # @param config [Config]
      # @return [Hash] JSON-ready skim
      def process content, config: Config.new(forms: [:flat])
        @config = config

        fm               = Sourcerer::YamlFrontmatter.extract(content)
        body             = Sourcerer::YamlFrontmatter.strip(content)
        offset           = content.lines.length - body.lines.length
        title, sections  = extract_title_and_sections(body, offset)

        result = {
          title:       title || fm['title'].to_s,
          frontmatter: fm
        }
        result[:sections_flat] = sections if @config.flat?
        result[:sections_tree] = build_tree(sections) if @config.tree?
        result
      end

      private

      # Scan body content for ATX headings.
      #
      # The first +#+ heading is treated as the document title (level 0) and
      # returned separately. All remaining headings are mapped to section level
      # +hashes - 1+ so that +##+ becomes level 1, +###+ becomes level 2, etc.
      #
      # Lines inside fenced code blocks (delimited by +```+ or +~~~+) are skipped
      # so that comment lines such as +# rubocop comment+ are not mistaken for headings.
      def extract_title_and_sections content, offset
        title    = nil
        sections = []
        in_fence = nil

        content.each_line.with_index(1) do |line, lineno|
          stripped  = line.chomp
          in_fence, fence_line = update_fence(stripped, in_fence)
          next if fence_line || in_fence

          m = stripped.match(MD_HEADING_RE)
          next unless m

          hashes = m[1].length
          if hashes == 1 && title.nil?
            title = m[2]
          else
            sections << { text: m[2], level: hashes - 1, starts_at: lineno + offset }
          end
        end

        [title, sections]
      end

      # Returns +[new_fence_state, is_fence_line]+ for the given stripped line.
      #
      # A fence line (the opening or closing +```+/+~~~+ marker) should always
      # be skipped by the caller regardless of the new fence state.
      def update_fence stripped, in_fence
        m = stripped.match(/\A(`{3,}|~{3,})/)
        return [in_fence, false] unless m
        return [m[1], true] if in_fence.nil?
        return [nil, true] if stripped.start_with?(in_fence)

        [in_fence, false]
      end

      # Build a nested section tree (Array) from a flat section list.
      #
      # Returns an Array of top-level (level 1) section nodes, each with a
      # +:sections+ array of children, mirroring the shape produced by
      # {Skimmer} for AsciiDoc documents.
      def build_tree sections
        roots = []
        stack = [{ level: 0, sections: roots }]

        sections.each do |h|
          node = h.merge(sections: [])
          stack.pop while stack.size > 1 && stack.last[:level] >= h[:level]
          stack.last[:sections] << node
          stack << node
        end

        roots
      end
    end
  end
end
