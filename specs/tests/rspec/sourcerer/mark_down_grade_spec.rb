# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Sourcerer::MarkDownGrade do
  let(:fixtures_dir) { File.expand_path('../../fixtures/mark_down_grade', __dir__) }

  before do
    described_class.bootstrap!(preserve_heading_ids: true, strip_internal_links: false)
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
  end
end
