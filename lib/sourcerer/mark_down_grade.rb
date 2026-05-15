# frozen_string_literal: true

# ReverseMarkdown Extensions
#
# Extends ReverseMarkdown with custom converters for better HTML-to-Markdown conversion
# Specifically designed for converting AsciiDoc-generated HTML to cleaner Markdown
#
# Usage:
#   require 'sourcerer'
#   Sourcerer::MarkDownGrade.bootstrap!
#   markdown = Sourcerer::MarkDownGrade.convert_html(html, github_flavored: true)
#
# See README.adoc for API usage details.

require 'reverse_markdown'
require 'nokogiri'

module Sourcerer
  module MarkDownGrade
    VERSION = '0.1.0'

    @config = {
      preserve_heading_ids: true,
      strip_internal_links: false,
      convert_tables_to_markdown: false
    }

    class << self
      attr_reader :config
    end

    # Setup all custom converters
    # Options:
    #   preserve_heading_ids: (default: true) Include <a id="..."> anchors before headings
    #   strip_internal_links: (default: false) Remove href from internal anchor links, keeping only text
    #   convert_tables_to_markdown: (default: false) Convert all tables to markdown UNLESS they have .no-markdown class
    def self.bootstrap! options={}
      @config.merge!(options)

      register_pre_converter
      register_heading_converters
      register_dl_converters
      register_inline_semantic_converters
      register_block_converters
      register_table_converter
      register_hr_converter
      register_blockquote_converter
      register_comment_converter
      register_link_converter
    end

    # Enhanced Pre converter to handle additional code block language patterns
    class CustomPre < ReverseMarkdown::Converters::Pre
      MAP = {
        'rb' => 'ruby',
        'yml' => 'yaml',
        'js' => 'javascript',
        'ts' => 'typescript',
        'sh' => 'bash',
        'zsh' => 'bash',
        'bash' => 'bash',
        'json' => 'json',
        'yaml' => 'yaml',
        'md' => 'markdown'
      }.freeze

      def language node
        # Parent handles highlight-*, brush:, etc.
        lang = super
        return normalize(lang) if lang

        candidates = []

        # 1) Inspect this <pre> and its <code> child
        code_child = node.at_css('code')
        [node, code_child].compact.each do |ele|
          collect_lang_hints(ele, candidates)
        end

        # 2) Inspect ancestors up to two levels (e.g., listingblock containers)
        node.ancestors.take(3).each do |anc|
          collect_lang_hints(anc, candidates)
        end

        candidates.compact!
        candidates.map! { |c| normalize(c) }
        candidates.find { |c| c } # first normalized non-nil
      end

      private

      def collect_lang_hints ele, acc
        return unless ele.respond_to?(:[])

        classes = ele['class'].to_s.split
        classes.each do |cls|
          if (m = cls.match(/\A(language|lang|highlight|source)-([A-Za-z0-9_+#-]+)\z/))
            acc << m[2]
          end
        end
        %w[data-lang data-language lang language].each do |attr|
          v = ele[attr]
          acc << v if v && !v.empty?
        end
      end

      def normalize value
        return nil if value.to_s.strip.empty?

        v = value.to_s.downcase
        v = MAP[v] || v
        # common aliases
        v = 'javascript' if %w[js nodejs node ecmascript].include?(v)
        v = 'yaml' if v == 'yml'
        v = 'bash' if %w[shell sh zsh].include?(v)
        v
      end
    end # class CustomPre

    # Heading converter: optionally preserve id attribute by emitting an anchor before the heading
    class HeadingWithId < ReverseMarkdown::Converters::Base
      def convert node, state={}
        if node.name == 'h6' && node['class'].to_s.split.include?('block-title')
          title_text = Sourcerer::MarkDownGrade.format_block_title(treat_children(node, state))
          return "#{title_text}  \n"
        end

        level = node.name[/\d/].to_i
        prefix = '#' * level
        heading = "#{prefix} #{treat_children(node, state)}\n"

        if Sourcerer::MarkDownGrade.config[:preserve_heading_ids]
          anchor = node['id'].to_s.strip
          anchor.empty? ? "\n#{heading}" : "\n<a id=\"#{anchor}\"></a>\n#{heading}"
        else
          "\n#{heading}"
        end
      end
    end

    # Definition list converter: preserve semantic list tags in output.
    class DlConverter < ReverseMarkdown::Converters::Base
      def convert node, state={}
        body = node.children.map { |child| treat(child, state) }.join.strip
        attrs = []
        attrs << %( class="#{node['class']}") if node['class']
        attrs << %( role="#{node['role']}") if node['role']
        "<dl#{attrs.join}>\n#{body}\n</dl>\n"
      end
    end

    # Definition term converter: preserves <dt> with classes, converts content.
    class DtConverter < ReverseMarkdown::Converters::Base
      def convert node, state={}
        class_attr = node['class'] ? %( class="#{node['class']}") : ''
        "<dt#{class_attr}>#{treat_children(node, state)}</dt>\n"
      end
    end

    # Definition description converter: preserves <dd>, converts nested content.
    class DdConverter < ReverseMarkdown::Converters::Base
      def convert node, state={}
        content = treat_children(node, state)
        attrs = []
        attrs << %( class="#{node['class']}") if node['class']
        attrs << %( role="#{node['role']}") if node['role']
        "<dd#{attrs.join}>\n#{content.strip}\n</dd>\n"
      end
    end

    # Preserve abstract content as plain text instead of markdown blockquote.
    class BlockquoteWithAbstract < ReverseMarkdown::Converters::Base
      def initialize
        super
        @default = ReverseMarkdown::Converters::Blockquote.new
      end

      def convert node, state={}
        classes = node.parent&.[]('class').to_s.split
        if (classes.include?('abstract') || classes.include?('quote-block')) && classes.include?('abstract')
          return "#{treat_children(node, state).strip}\n\n"
        end

        @default.convert(node, state)
      end
    end

    # Normalize horizontal-rule markdown style.
    class HrConverter < ReverseMarkdown::Converters::Base
      def convert _node, _state={}
        "\n---\n\n"
      end
    end

    # Preserve inline semantic tags when class/role attributes are present.
    class InlineSemanticConverter < ReverseMarkdown::Converters::Base
      def initialize tag_name, fallback_converter
        super()
        @tag_name = tag_name
        @fallback_converter = fallback_converter
      end

      def convert node, state={}
        return @fallback_converter.convert(node, state) unless preserve_semantic_tag?(node)

        attrs = []
        attrs << %( class="#{node['class']}") if node['class']
        attrs << %( role="#{node['role']}") if node['role']
        "<#{@tag_name}#{attrs.join}>#{treat_children(node, state)}</#{@tag_name}>"
      end

      private

      def preserve_semantic_tag? node
        [node['class'], node['role']].any? { |val| !val.to_s.strip.empty? }
      end
    end

    # Special Div converter: handles sidebarblock and admonitionblock specifically; delegates others to default Div.
    class SpecialDivConverter < ReverseMarkdown::Converters::Base
      def initialize
        super
        @default_div = ReverseMarkdown::Converters::Div.new
      end

      def convert node, state={}
        classes = node['class'].to_s.split
        if classes.include?('sidebarblock')
          convert_sidebarblock(node, state)
        elsif classes.include?('admonitionblock')
          convert_admonitionblock(node, state)
        else
          @default_div.convert(node, state)
        end
      end

      private

      def convert_sidebarblock node, state={}
        container = node.at_css('div.content') || node
        title_node = container.at_css('> .title') || node.at_css('> .title')
        title_text = if title_node
                       Sourcerer::MarkDownGrade.normalize_block_title(treat_children(title_node, state))
                     else
                       'Sidebar'
                     end
        body_nodes = container.children.reject { |c| c.element? && c['class'].to_s.split.include?('title') }
        body_md = body_nodes.map { |c| treat(c, state) }.join.strip
        block_id = (node['id'] || container['id']).to_s.strip
        marker = block_id.empty? ? 'block::sidebar' : "block::sidebar id=#{block_id}"
        [
          '---',
          "<!-- #{marker} -->",
          "##### [SIDEBAR] #{title_text}",
          '',
          body_md,
          '<!-- end::sidebar -->',
          '---',
          ''
        ].join("\n")
      end

      def convert_admonitionblock node, state={}
        # Render Asciidoctor admonition as a Markdown blockquote with bold label
        classes = node['class'].to_s.split
        type = (classes & %w[note tip warning caution important]).first ||
               node.at_css('td.icon > .title')&.text&.downcase || 'note'
        type_up = type.to_s.strip.upcase

        container = node.at_css('td.content') || node.at_css('div.content') || node

        # Optional content title inside the content cell
        content_title_node = container.at_css('> .title')
        inline_title = if content_title_node
                         title = treat_children(content_title_node, state).strip.gsub(/\s+/, ' ')
                         Sourcerer::MarkDownGrade.clean_admonition_inline_title(title, type)
                       end

        # Body is all children except the content title
        body_nodes = container.children.reject { |c| c.element? && c['class'].to_s.split.include?('title') }
        body_md = body_nodes.map { |c| treat(c, state) }.join.strip

        label = "**#{type_up}:**"
        label += " #{inline_title}" if inline_title && !inline_title.empty?

        # Insert label at first non-empty line, then prefix every line as a blockquote
        lines = body_md.split("\n")
        if lines.empty?
          lines = [label]
        else
          idx = lines.index { |l| !l.strip.empty? } || 0
          lines[idx] = "#{label} #{lines[idx].lstrip}".rstrip
        end

        quoted = lines.map { |l| l.strip.empty? ? '>' : "> #{l}" }.join("\n")
        "#{quoted}\n"
      end
    end # class SpecialDivConverter

    # Semantic block converter for html5s tags like <section>, <aside>, <figure>, and <nav>.
    class SemanticBlockConverter < ReverseMarkdown::Converters::Base
      def convert node, state={}
        classes = node['class'].to_s.split

        case node.name
        when 'aside'
          return convert_sidebar(node, state) if classes.include?('sidebar')
          return convert_admonition(node, state) if classes.include?('admonition-block')
        when 'section'
          return convert_admonition(node, state) if classes.include?('admonition-block')
          return convert_toc_section(node, state) if classes.include?('toc')
        when 'figure'
          return convert_figure(node, state)
        when 'nav'
          return convert_toc_nav(node, state) if classes.include?('toc')
        end

        body = treat_children(node, state).strip
        body.empty? ? '' : "#{body}\n\n"
      end

      private

      def convert_sidebar node, state={}
        title_node = node.at_css('> .block-title')
        title_text = if title_node
                       Sourcerer::MarkDownGrade.normalize_block_title(treat_children(title_node, state))
                     else
                       'Sidebar'
                     end
        body_nodes = node.children.reject { |child| child == title_node }
        body_md = body_nodes.map { |child| treat(child, state) }.join.strip
        block_id = node['id'].to_s.strip
        marker = block_id.empty? ? 'block::sidebar' : "block::sidebar id=#{block_id}"
        [
          '---',
          "<!-- #{marker} -->",
          "##### [SIDEBAR] #{title_text}",
          '',
          body_md,
          '<!-- end::sidebar -->',
          '---',
          ''
        ].join("\n")
      end

      def convert_admonition node, state={}
        classes = node['class'].to_s.split
        title_label_text = node.at_css('.title-label')&.text
        title_label_text = title_label_text.sub(':', '').downcase if title_label_text
        icon_title_text = node.at_css('td.icon > .title')&.text
        icon_title_text = icon_title_text.downcase if icon_title_text

        type = (classes & %w[note tip warning caution important]).first ||
               title_label_text ||
               icon_title_text || 'note'
        type_up = type.to_s.strip.upcase

        title_node = node.at_css('> .block-title') || node.at_css('td.content > .title')
        inline_title = if title_node
                         title = treat_children(title_node, state).strip.gsub(/\s+/, ' ')
                         Sourcerer::MarkDownGrade.clean_admonition_inline_title(title, type)
                       end

        body_nodes = node.children.reject { |child| child == title_node }
        body_md = body_nodes.map { |child| treat(child, state) }.join.strip

        label = "**#{type_up}:**"
        label += " #{inline_title}" if inline_title && !inline_title.empty?

        lines = body_md.split("\n")
        lines = [label] if lines.empty?
        idx = lines.index { |line| !line.strip.empty? } || 0
        lines[idx] = "#{label} #{lines[idx].lstrip}".rstrip

        quoted_lines = lines.map { |line| line.strip.empty? ? '>' : "> #{line}" }.join("\n")
        "#{quoted_lines}\n"
      end

      def convert_figure node, state={}
        classes = node['class'].to_s.split
        title_node = node.at_css('> figcaption')
        title = title_node ? Sourcerer::MarkDownGrade.normalize_block_title(treat_children(title_node, state)) : nil

        if classes.include?('listing-block')
          pre = node.at_css('pre')
          code_md = pre ? treat(pre, state).strip : treat_children(node, state).strip
          title_md = title && !title.empty? ? Sourcerer::MarkDownGrade.block_title_line(title) : ''
          return "#{title_md}#{code_md}\n\n"
        end

        if classes.include?('example-block')
          body_node = node.at_css('> .example')
          body_md = body_node ? treat_children(body_node, state).strip : treat_children(node, state).strip
          class_attr = node['class'].to_s.strip
          class_attr = 'example-block' if class_attr.empty?
          figcaption = ''
          if title && !title.empty?
            figcaption_text = Sourcerer::MarkDownGrade.format_block_title(title)
            figcaption = "<figcaption>#{figcaption_text}</figcaption>\n"
          end
          return "<figure class=\"#{class_attr}\">\n#{figcaption}#{body_md}\n</figure>\n\n"
        end

        content_nodes = node.children.reject { |child| child == title_node }
        content_md = content_nodes.map { |child| treat(child, state) }.join.strip
        title_md = title && !title.empty? ? "#{title}\n\n" : ''
        "#{title_md}#{content_md}\n\n"
      end

      def convert_toc_nav node, state={}
        heading = node.at_css('h2, #toc-title')
        heading_text = heading ? treat_children(heading, state).strip : 'Table of Contents'
        list = node.at_css('ol, ul')
        list_md = list ? treat(list, state).strip : ''
        list_md = list_md.gsub(/\[\d+\.\s+([^\]]+)\]\(#/, '[\1](#')
        "#{heading_text}\n\n#{list_md}\n\n"
      end

      def convert_toc_section node, state={}
        convert_toc_nav(node, state)
      end
    end

    # Passthrough Tables: preserve HTML tables as-is (except admonition internals handled elsewhere).
    # Tables with "to-markdown" class are converted via ReverseMarkdown instead.
    # Supports both html5 (class on <table>) and html5s (class on parent <div class="table-block">).
    # Per-table classes (.to-markdown, .no-markdown) override the global conversion mode.
    class TablePassthrough < ReverseMarkdown::Converters::Base
      def initialize
        super
        @markdown_converter = ReverseMarkdown::Converters::Table.new
      end

      def convert node, state={}
        global_mode = Thread.current[:sourcerer_table_conversion_mode] || false

        # Check for per-table classes (on table or parent wrapper)
        has_to_markdown = check_class_on_node(node, 'to-markdown')
        has_no_markdown = check_class_on_node(node, 'no-markdown')

        # Also check parent <div class="table-block"> wrapper (html5s backend)
        parent_div = node.parent
        if parent_div && parent_div.name == 'div'
          has_to_markdown ||= check_class_on_node(parent_div, 'to-markdown')
          has_no_markdown ||= check_class_on_node(parent_div, 'no-markdown')
        end

        # Determine whether to convert (per-table classes override global mode)
        should_convert = if has_no_markdown
                           false # .no-markdown always prevents conversion
                         elsif has_to_markdown
                           true  # .to-markdown always forces conversion
                         else
                           global_mode # Use global table conversion mode
                         end

        if should_convert
          @markdown_converter.convert(node, state)
        else
          "#{node.to_html}\n"
        end
      end

      private

      def check_class_on_node node, class_name
        node['class'].to_s.split.include?(class_name)
      end
    end

    # HTML Comment converter: preserve comments and ensure a trailing newline.
    class HtmlComment < ReverseMarkdown::Converters::Base
      def convert node, _state={}
        out = node.to_html
        out.end_with?("\n") ? out : "#{out}\n"
      end
    end

    # Link converter that strips internal anchor links when enabled.
    class LinkConverter < ReverseMarkdown::Converters::Base
      def convert node, state={}
        id = node['id'].to_s.strip
        href = node['href'].to_s

        if href.empty? && !id.empty?
          %(<a id="#{id}"></a>)
        elsif href.start_with?('#') && Sourcerer::MarkDownGrade.config[:strip_internal_links]
          treat_children(node, state)
        else
          ReverseMarkdown::Converters::A.new.convert(node, state)
        end
      end
    end

    # List item converter that handles nested lists and checklists.
    class LiWithNestedLists < ReverseMarkdown::Converters::Base
      def convert node, state={}
        indentation = indentation_from(state)

        content_parts = []
        nested_lists = []

        # Check for checkbox in this LI or its first paragraph
        # Asciidoctor often puts the checkbox inside a <p> tag
        checkbox = node.at_xpath('./input[@type="checkbox"] | ./p/input[@type="checkbox"][1]')

        prefix = if checkbox
                   is_checked = checkbox['checked'] || checkbox['data-item-complete'] == '1'
                   # Remove the checkbox from the DOM so it doesn't get rendered again
                   checkbox.remove
                   is_checked ? '<!--CHECKBOX_CHECKED--> ' : '<!--CHECKBOX_UNCHECKED--> '
                 else
                   prefix_for(node)
                 end

        node.children.each do |child|
          if child.element? && %w[ol ul].include?(child.name)
            nested_lists << child
          else
            content_parts << treat(child, state)
          end
        end

        content = content_parts.join.strip
        result = "#{indentation}#{prefix}#{content}\n"

        nested_lists.each do |nested_list|
          nested_state = state.merge(ol_count: state.fetch(:ol_count, 0) + 1)
          nested_md = treat(nested_list, nested_state).strip
          result << "#{nested_md}\n" unless nested_md.empty?
        end

        result
      end

      private

      def prefix_for node
        if node.parent.name == 'ol'
          index = node.parent.xpath('li').index(node)
          "#{index.to_i + 1}. "
        else
          '- '
        end
      end

      def indentation_from state
        length = state.fetch(:ol_count, 0)
        '   ' * [length - 1, 0].max
      end
    end # class LiWithNestedLists

    # Module-level converter registration methods

    # Register the enhanced Pre converter.
    def self.register_pre_converter
      ReverseMarkdown::Converters.register :pre, CustomPre.new
    end

    # Register heading converter that preserves ids.
    def self.register_heading_converters
      converter = HeadingWithId.new
      ReverseMarkdown::Converters.register :h1, converter
      ReverseMarkdown::Converters.register :h2, converter
      ReverseMarkdown::Converters.register :h3, converter
      ReverseMarkdown::Converters.register :h4, converter
      ReverseMarkdown::Converters.register :h5, converter
      ReverseMarkdown::Converters.register :h6, converter
    end

    # Register all definition list converters.
    def self.register_dl_converters
      ReverseMarkdown::Converters.register :dl, DlConverter.new
      ReverseMarkdown::Converters.register :dt, DtConverter.new
      ReverseMarkdown::Converters.register :dd, DdConverter.new
    end

    # Register inline semantic converters.
    def self.register_inline_semantic_converters
      ReverseMarkdown::Converters.register(:em, InlineSemanticConverter.new('em', ReverseMarkdown::Converters::Em.new))
      ReverseMarkdown::Converters.register(:strong, InlineSemanticConverter.new('strong', ReverseMarkdown::Converters::Strong.new))
      ReverseMarkdown::Converters.register(:code, InlineSemanticConverter.new('code', ReverseMarkdown::Converters::Code.new))
    end

    # Register block converter for special div classes.
    def self.register_block_converters
      ReverseMarkdown::Converters.register :div, SpecialDivConverter.new
      semantic = SemanticBlockConverter.new
      ReverseMarkdown::Converters.register :section, semantic
      ReverseMarkdown::Converters.register :aside, semantic
      ReverseMarkdown::Converters.register :figure, semantic
      ReverseMarkdown::Converters.register :nav, semantic
    end

    # Register table passthrough converter.
    def self.register_table_converter
      ReverseMarkdown::Converters.register :table, TablePassthrough.new
    end

    # Register horizontal-rule converter.
    def self.register_hr_converter
      ReverseMarkdown::Converters.register :hr, HrConverter.new
    end

    # Register blockquote converter with abstract handling.
    def self.register_blockquote_converter
      ReverseMarkdown::Converters.register :blockquote, BlockquoteWithAbstract.new
    end

    # Register HTML comment converter.
    def self.register_comment_converter
      ReverseMarkdown::Converters.register :comment, HtmlComment.new
    end

    # Register custom link converter to support id-only anchors and optional stripping.
    def self.register_link_converter
      ReverseMarkdown::Converters.register :a, LinkConverter.new
    end

    # Normalize block titles so escaped inline emphasis from html5s is converted
    # to markdown emphasis consistently with html5 conversions.
    def self.normalize_block_title text
      normalized = text.to_s.strip.gsub(/\s+/, ' ')
      normalized = normalized.gsub(/\\\*([^*]+)\\\*/, '**\\1**')
      normalized.gsub(/(?<![\\*])\*([^*]+)\*(?!\*)/, '**\\1**')
    end

    # Apply strong formatting consistently across block titles.
    def self.format_block_title text
      normalized = normalize_block_title(text)
      plain = normalized.gsub(/\*\*([^*]+)\*\*/, '\\1')
      plain = plain.gsub(/\*([^*]+)\*/, '\\1').strip
      plain.empty? ? normalized : "**#{plain}**"
    end

    # Render a block-title line with hard line break for immediate continuation.
    def self.block_title_line text
      "#{format_block_title(text)}  \n"
    end

    # Remove duplicated admonition label prefixes from converted inline titles.
    def self.clean_admonition_inline_title title, type
      normalized = title.to_s.strip
      label = "#{type.to_s.strip.capitalize}:"
      normalized = normalized.sub(/\A#{Regexp.escape(label)}\s*/i, '')
      normalized.empty? ? nil : normalized
    end

    # Convert HTML into Markdown with MarkDownGrade converters.
    # Options include:
    #   convert_tables_to_markdown: Override global config for table conversion (true/false)
    def self.convert_html html, options={}
      bootstrap! unless @setup_complete
      @setup_complete = true

      # Determine effective table conversion mode
      effective_mode = determine_table_conversion_mode(html.to_s, options)
      Thread.current[:sourcerer_table_conversion_mode] = effective_mode

      begin
        normalized_html = normalize_html_for_markdown(html.to_s)
        markdown = ReverseMarkdown.convert(normalized_html, options)
        markdown = markdown.gsub(/(\*\*[^\n]+\*\*  \n)\n+(?=\S)/, '\\1')
        markdown = markdown.gsub(/<figcaption>\s+/, '<figcaption>')
        markdown = markdown.gsub(%r{\s+</figcaption>}, '</figcaption>')

        markdown.gsub('<!--CHECKBOX_CHECKED-->', '- [x]')
                .gsub('<!--CHECKBOX_UNCHECKED-->', '- [ ]')
      ensure
        Thread.current[:sourcerer_table_conversion_mode] = nil
      end
    end

    def self.convert html, options={}
      convert_html(html, options)
    end

    # Normalize Asciidoctor HTML variants before HTML->Markdown conversion.
    def self.normalize_html_for_markdown html_body
      fragment = Nokogiri::HTML::DocumentFragment.parse(html_body)
      normalize_abstract_nodes!(fragment)
      normalize_footnote_nodes!(fragment)
      clean_html5s_tables!(fragment)
      fragment.to_html
    end

    # Convert abstract quote wrappers into plain abstract paragraph wrappers.
    def self.normalize_abstract_nodes! fragment
      fragment.css('div.quoteblock.abstract, div.quote-block.abstract').each do |wrapper|
        blockquote = wrapper.at_css('blockquote')
        next unless blockquote

        abstract_wrapper = Nokogiri::XML::Node.new('div', fragment)
        abstract_wrapper['class'] = 'abstract'
        paragraph = Nokogiri::XML::Node.new('p', fragment)
        paragraph.inner_html = blockquote.inner_html
        abstract_wrapper.add_child(paragraph)
        wrapper.replace(abstract_wrapper)
      end
    end

    # Add canonical footnote anchors for both html5 and html5s footnote structures.
    def self.normalize_footnote_nodes! fragment
      selectors = [
        'section.footnotes ol.footnotes > li.footnote[id]',
        'div#footnotes > div.footnote[id]'
      ]
      fragment.css(selectors.join(', ')).each do |footnote_node|
        anchor_id = canonical_footnote_anchor_id(footnote_node)
        next if anchor_id.to_s.empty?
        next if footnote_node.children.any? { |node| node.element? && node.name == 'a' && node['id'] == anchor_id }

        anchor = Nokogiri::XML::Node.new('a', fragment)
        anchor['id'] = anchor_id

        first_child = footnote_node.children.first
        if first_child
          first_child.add_previous_sibling(anchor)
        else
          footnote_node.add_child(anchor)
        end
      end
    end

    # Resolve the canonical markdown anchor id used by in-text footnote links.
    def self.canonical_footnote_anchor_id footnote_node
      raw_id = footnote_node['id'].to_s.strip
      return "_footnote_#{::Regexp.last_match(1)}" if raw_id.match(/\A_footnote(?:def)?_(\d+)\z/)

      backref = footnote_node.at_css('a.footnote-backref, a[href^="#_footnoteref_"]')
      href = backref&.[]('href').to_s
      return "_footnote_#{::Regexp.last_match(1)}" if href.match(/\A#_footnoteref_(\d+)\z/)

      raw_id.empty? ? nil : raw_id
    end

    # Clean HTML5s table artifacts: remove colgroup elements and class/style attributes from cells.
    # This normalizes tables generated by the asciidoctor-html5s backend for safer Markdown conversion.
    #
    # @param fragment [Nokogiri::HTML::DocumentFragment] The HTML fragment to clean.
    # @return [void] Modifies fragment in place.
    def self.clean_html5s_tables! fragment
      # Remove all colgroup elements
      fragment.css('colgroup').each(&:remove)

      # Remove class and style attributes from table cells and rows
      fragment.css('td, th, tr').each do |cell|
        cell.delete('class')
        cell.delete('style')
      end
    end

    # Determine the effective table conversion mode from options, frontmatter, or global config.
    #
    # Precedence:
    # 1. Explicit convert_tables_to_markdown option in parameters
    # 2. Document-level setting from frontmatter (YAML) or page attributes (AsciiDoc)
    # 3. Global config setting
    #
    # @param html_body [String] The HTML document body.
    # @param options [Hash] Optional override.
    # @return [Boolean] Whether tables should be converted to markdown by default.
    def self.determine_table_conversion_mode html_body, options
      # Explicit option takes precedence
      return options[:convert_tables_to_markdown] if options.key?(:convert_tables_to_markdown)

      # Extract from document metadata
      document_mode = extract_table_conversion_mode_from_html(html_body)
      return document_mode unless document_mode.nil?

      # Fall back to global config
      @config[:convert_tables_to_markdown]
    end

    # Extract table conversion mode from document frontmatter or page attributes.
    #
    # Checks for:
    # - YAML frontmatter key: tables-to-markdown
    # - AsciiDoc page attribute: page-tables-to-markdown
    #
    # @param html_body [String] The HTML document body.
    # @return [Boolean, nil] The setting if found, nil otherwise.
    def self.extract_table_conversion_mode_from_html html_body
      # Try to extract YAML frontmatter
      frontmatter = Sourcerer::YamlFrontmatter.extract(html_body)
      return string_to_boolean(frontmatter['tables-to-markdown']) if frontmatter.key?('tables-to-markdown')

      # Try to find page-tables-to-markdown in HTML comments or metadata
      # (This would be set by AsciiDoc's page attributes)
      if html_body.include?('page-tables-to-markdown')
        # Look for data attributes or comments that might encode this
        if html_body.match?(/page-tables-to-markdown['"]?\s*[:=]\s*['"]*true/i)
          return true
        elsif html_body.match?(/page-tables-to-markdown['"]?\s*[:=]\s*['"]*false/i)
          return false
        end
      end

      nil
    end

    # Convert a string representation to a boolean value.
    #
    # @param value [String, Boolean, nil] The value to convert.
    # @return [Boolean, nil] Boolean if value is truthy string, nil if unclear.
    def self.string_to_boolean value
      case value.to_s.downcase.strip
      when 'true', '1', 'yes', 'on'
        true
      when 'false', '0', 'no', 'off', ''
        false
      end
    end

    private_class_method :normalize_html_for_markdown,
                         :normalize_abstract_nodes!,
                         :normalize_footnote_nodes!,
                         :canonical_footnote_anchor_id,
                         :clean_html5s_tables!,
                         :determine_table_conversion_mode,
                         :extract_table_conversion_mode_from_html,
                         :string_to_boolean
  end # module MarkDownGrade
end # module Sourcerer

# Transitional alias for existing downstream callers.
MarkDownGrade = Sourcerer::MarkDownGrade unless defined?(MarkDownGrade)
