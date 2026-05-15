# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Sourcerer::MarkDownGrade do
  let(:fixtures_dir) { File.expand_path('../../fixtures/mark_down_grade', __dir__) }

  before do
    described_class.bootstrap!(
      preserve_heading_ids: true, strip_internal_links: false,
      convert_tables_to_markdown: false)
  end

  describe '.convert_html' do
    def read_fixture name
      File.read(File.join(fixtures_dir, name))
    end

    def convert_html_fragment html
      described_class.convert_html(html, github_flavored: true)
    end

    def abstract_wrappers_normalized? markdown
      markdown.include?('Abstract from quoteblock wrapper.') &&
        markdown.include?('Abstract from quote-block wrapper.') &&
        !markdown.include?('> Abstract from quoteblock wrapper.') &&
        !markdown.include?('> Abstract from quote-block wrapper.')
    end

    it 'preserves heading anchors by default' do
      markdown = convert_html_fragment('<h2 id="intro">Introduction</h2>')
      expect(markdown).to include('<a id="intro"></a>')
    end

    it 'preserves heading text as markdown headings' do
      markdown = convert_html_fragment('<h2 id="intro">Introduction</h2>')
      expect(markdown).to include('## Introduction')
    end

    it 'preserves semantic definition list tags' do
      html = '<dl><dt class="hdlist1">Term</dt><dd><p>Description</p></dd></dl>'
      markdown = convert_html_fragment(html)
      expect(markdown).to include('<dl>', '<dt class="hdlist1">Term</dt>', '<dd>', 'Description')
    end

    it 'preserves toc internal links as markdown anchors by default' do
      markdown = convert_html_fragment('<ul><li><a href="#intro">Introduction</a></li></ul>')
      expect(markdown).to include('[Introduction](#intro)')
    end

    it 'strips internal anchor links when configured' do
      described_class.bootstrap!(strip_internal_links: true, preserve_heading_ids: true)
      markdown = convert_html_fragment('<p><a href="#intro">Introduction</a></p>')
      expect(markdown).not_to include('(#intro)')
    end

    it 'retains link text when stripping internal anchor links' do
      described_class.bootstrap!(strip_internal_links: true, preserve_heading_ids: true)
      markdown = convert_html_fragment('<p><a href="#intro">Introduction</a></p>')
      expect(markdown).to include('Introduction')
    end

    it 'preserves inline semantic tags with class or role attributes' do
      html = '<p><em class="role">term</em> and <code role="literal">x</code></p>'
      markdown = convert_html_fragment(html)
      expect(markdown).to include('<em class="role">term</em>', '<code role="literal">x</code>')
    end

    it 'normalizes abstract wrappers from fixture html without blockquote markers' do
      markdown = convert_html_fragment(read_fixture('abstract-wrappers.html'))
      expect(abstract_wrappers_normalized?(markdown)).to be(true)
    end

    it 'injects explicit footnote anchors for fixture footnote backlinks' do
      markdown = convert_html_fragment(read_fixture('footnote-backref.html'))
      expect(markdown).to include(
        '<a id="_footnote_1"></a>',
        '1. <a id="_footnote_1"></a> This is a fixture footnote. [↩](#_footnoteref_1 "Jump to note")')
    end

    it 'normalizes html5 footnote definitions to canonical anchor ids' do
      markdown = convert_html_fragment(read_fixture('footnote-definitions.html'))
      expect(markdown).to include(
        '<a id="_footnote_1"></a>',
        'This is an html5 fixture footnote.')
    end

    describe 'HTML5s table cleaning and markdown conversion' do
      it 'removes colgroup elements from tables' do
        html = <<~HTML
          <table>
            <colgroup><col style="width:50%"></colgroup>
            <tr><td>Cell 1</td></tr>
          </table>
        HTML
        markdown = convert_html_fragment(html)
        expect(markdown).not_to include('<colgroup>')
        expect(markdown).to include('<table>')
      end

      it 'removes class attributes from table cells' do
        html = '<table><tr><td class="cell-style">Content</td></tr></table>'
        markdown = convert_html_fragment(html)
        expect(markdown).not_to include('class="cell-style"')
        expect(markdown).to include('Content')
      end

      it 'removes style attributes from table cells' do
        html = '<table><tr><td style="color:red;">Content</td></tr></table>'
        markdown = convert_html_fragment(html)
        expect(markdown).not_to include('style="color:red;"')
        expect(markdown).to include('Content')
      end

      it 'removes class and style attributes from th elements' do
        html = '<table><tr><th class="header" style="bold">Header</th></tr></table>'
        markdown = convert_html_fragment(html)
        expect(markdown).not_to include('class="header"')
        expect(markdown).not_to include('style="bold"')
        expect(markdown).to include('Header')
      end

      it 'removes class and style attributes from tr elements' do
        html = '<table><tr class="row-class" style="background:gray;"><td>Content</td></tr></table>'
        markdown = convert_html_fragment(html)
        expect(markdown).not_to include('class="row-class"')
        expect(markdown).not_to include('style="background:gray;"')
        expect(markdown).to include('Content')
      end

      it 'preserves table structure after cleaning' do
        html = <<~HTML
          <table>
            <colgroup><col></colgroup>
            <tr class="row"><td class="cell">A</td><td>B</td></tr>
            <tr><td>C</td><td style="color:red;">D</td></tr>
          </table>
        HTML
        markdown = convert_html_fragment(html)
        expect(markdown).to include('| A | B |').or include('A')
        expect(markdown).to include('| C | D |').or include('D')
      end

      it 'converts table with to-markdown class to markdown table syntax' do
        html = '<table class="to-markdown"><tr><td>A</td><td>B</td></tr></table>'
        markdown = convert_html_fragment(html)
        # ReverseMarkdown creates markdown table syntax with pipes
        expect(markdown).to include('|')
        expect(markdown).to include('A')
        expect(markdown).to include('B')
      end

      it 'converts table with to-markdown class when wrapped in html5s div wrapper' do
        # html5s backend wraps tables in <div class="table-block">
        html = '<div class="table-block to-markdown"><table><tr><td>Row1</td></tr></table></div>'
        markdown = convert_html_fragment(html)
        expect(markdown).to include('|')
        expect(markdown).to include('Row1')
      end

      it 'detects to-markdown role on html5s wrapper div even without table class' do
        # The role on the wrapper should trigger conversion
        html = '<div class="table-block to-markdown"><table class="frame-all"><tr><td>Data</td></tr></table></div>'
        markdown = convert_html_fragment(html)
        expect(markdown).to include('|')
        expect(markdown).to include('Data')
      end

      it 'converts table with to-markdown class when mixed with other classes' do
        html = '<table class="data to-markdown"><tr><td>Row1</td></tr></table>'
        markdown = convert_html_fragment(html)
        expect(markdown).to include('|')
        expect(markdown).to include('Row1')
      end

      it 'converts table when to-markdown is mixed with other wrapper classes in html5s' do
        html = '<div class="table-block frame-all to-markdown other">' \
               '<table class="grid-all"><tr><td>Mixed</td></tr></table></div>'
        markdown = convert_html_fragment(html)
        expect(markdown).to include('|')
        expect(markdown).to include('Mixed')
      end

      it 'preserves tables without to-markdown as HTML when passthrough is default' do
        html = '<table><tr><td>Data</td></tr></table>'
        markdown = convert_html_fragment(html)
        # Without to-markdown, should remain as HTML
        expect(markdown).to include('<table>')
      end

      it 'strips colgroup, class, and style from complex table with to-markdown class' do
        html = <<~HTML
          <table class="to-markdown">
            <colgroup><col style="width:30%;"></colgroup>
            <tr class="header" style="background:blue;">
              <th class="title-cell" style="color:white;">Header</th>
            </tr>
            <tr>
              <td class="data-cell" style="padding:10px;">Content</td>
            </tr>
          </table>
        HTML
        markdown = convert_html_fragment(html)
        expect(markdown).not_to include('<colgroup>')
        expect(markdown).not_to include('class="')
        expect(markdown).not_to include('style="')
      end

      it 'converts complex table with to-markdown class to markdown syntax' do
        html = <<~HTML
          <table class="to-markdown">
            <tr><th>Header</th></tr>
            <tr><td>Content</td></tr>
          </table>
        HTML
        markdown = convert_html_fragment(html)
        expect(markdown).to include('|')
        expect(markdown).to include('Header')
      end

      it 'cleans multiple tables independently' do
        html = <<~HTML
          <table>
            <colgroup><col></colgroup>
            <tr><td class="cell">Table1</td></tr>
          </table>
          <table class="to-markdown">
            <tr><td class="cell">Table2</td></tr>
          </table>
        HTML
        markdown = convert_html_fragment(html)
        expect(markdown).not_to include('<colgroup>')
        expect(markdown).not_to include('class="cell"')
        expect(markdown).to include('Table1')
        expect(markdown).to include('Table2')
      end

      describe 'global table conversion mode' do # rubocop:disable RSpec/NestedGroups
        it 'converts all tables to markdown when global mode is enabled' do
          described_class.bootstrap!(convert_tables_to_markdown: true)
          html = '<table><tr><td>A</td><td>B</td></tr></table>'
          markdown = convert_html_fragment(html)
          expect(markdown).to include('|')
          expect(markdown).to include('A')
          expect(markdown).to include('B')
        end

        it 'keeps all tables as HTML when global mode is disabled (default)' do
          described_class.bootstrap!(convert_tables_to_markdown: false)
          html = '<table><tr><td>A</td><td>B</td></tr></table>'
          markdown = convert_html_fragment(html)
          expect(markdown).to include('<table>')
          expect(markdown).not_to include('| A |')
        end

        it 'respects .no-markdown class to prevent conversion with global mode enabled' do
          described_class.bootstrap!(convert_tables_to_markdown: true)
          html = '<table class="no-markdown"><tr><td>Data</td></tr></table>'
          markdown = convert_html_fragment(html)
          expect(markdown).not_to include('|')
          expect(markdown).to include('<table')
          expect(markdown).to include('Data')
        end

        it 'respects .no-markdown on html5s wrapper to prevent conversion' do
          described_class.bootstrap!(convert_tables_to_markdown: true)
          html = '<div class="table-block no-markdown"><table><tr><td>Data</td></tr></table></div>'
          markdown = convert_html_fragment(html)
          expect(markdown).not_to include('|')
          expect(markdown).to include('<table')
        end

        it 'respects .to-markdown class to force conversion with global mode disabled' do
          described_class.bootstrap!(convert_tables_to_markdown: false)
          html = '<table class="to-markdown"><tr><td>Data</td></tr></table>'
          markdown = convert_html_fragment(html)
          expect(markdown).to include('|')
          expect(markdown).to include('Data')
        end

        it 'respects .to-markdown on html5s wrapper to force conversion' do
          described_class.bootstrap!(convert_tables_to_markdown: false)
          html = '<div class="table-block to-markdown"><table><tr><td>Data</td></tr></table></div>'
          markdown = convert_html_fragment(html)
          expect(markdown).to include('|')
          expect(markdown).to include('Data')
        end

        it 'prefers .no-markdown over global conversion mode' do
          described_class.bootstrap!(convert_tables_to_markdown: true)
          html = '<table class="no-markdown to-markdown"><tr><td>Data</td></tr></table>'
          markdown = convert_html_fragment(html)
          expect(markdown).not_to include('|')
          expect(markdown).to include('<table')
          expect(markdown).to include('Data')
        end

        it 'prefers .to-markdown over default passthrough' do
          described_class.bootstrap!(convert_tables_to_markdown: false)
          html = '<table class="to-markdown no-markdown-other"><tr><td>Data</td></tr></table>'
          markdown = convert_html_fragment(html)
          expect(markdown).to include('|')
        end
      end

      describe 'frontmatter-based table conversion mode' do # rubocop:disable RSpec/NestedGroups
        it 'extracts tables-to-markdown from YAML frontmatter' do
          html_with_frontmatter = <<~HTML
            ---
            tables-to-markdown: true
            ---

            <table><tr><td>Data</td></tr></table>
          HTML
          described_class.bootstrap!(convert_tables_to_markdown: false)
          markdown = described_class.convert_html(html_with_frontmatter)
          expect(markdown).to include('|')
          expect(markdown).to include('Data')
        end

        it 'respects tables-to-markdown: false in YAML frontmatter' do
          html_with_frontmatter = <<~HTML
            ---
            tables-to-markdown: false
            ---

            <table><tr><td>Data</td></tr></table>
          HTML
          described_class.bootstrap!(convert_tables_to_markdown: true)
          markdown = described_class.convert_html(html_with_frontmatter)
          expect(markdown).to include('<table>')
        end

        it 'overrides global config with frontmatter setting' do
          html_with_frontmatter = <<~HTML
            ---
            layout: docs
            tables-to-markdown: true
            ---

            <table><tr><td>Override</td></tr></table>
          HTML
          described_class.bootstrap!(convert_tables_to_markdown: false)
          markdown = described_class.convert_html(html_with_frontmatter)
          expect(markdown).to include('|')
          expect(markdown).to include('Override')
        end

        it 'accepts per-table .no-markdown to override frontmatter setting' do
          html_with_frontmatter = <<~HTML
            ---
            tables-to-markdown: true
            ---

            <table class="no-markdown"><tr><td>Exempt</td></tr></table>
          HTML
          markdown = described_class.convert_html(html_with_frontmatter)
          expect(markdown).not_to include('|')
          expect(markdown).to include('<table')
          expect(markdown).to include('Exempt')
        end

        it 'accepts convert_tables_to_markdown option to override frontmatter' do
          html_with_frontmatter = <<~HTML
            ---
            tables-to-markdown: true
            ---

            <table><tr><td>Data</td></tr></table>
          HTML
          described_class.bootstrap!
          markdown = described_class.convert_html(html_with_frontmatter, convert_tables_to_markdown: false)
          expect(markdown).to include('<table>')
        end
      end
    end
  end
end
