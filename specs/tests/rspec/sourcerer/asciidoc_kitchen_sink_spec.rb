# frozen_string_literal: true

require 'fileutils'
require_relative '../spec_helper'

RSpec.describe Sourcerer::AsciiDoc do
  let(:fixture_path) { File.expand_path('../../fixtures/kitchen-sink.adoc', __dir__) }
  let(:results_dir) { File.expand_path('../../results/mark_down_grade', __dir__) }

  def html_tag_count markdown
    markdown.scan(/<[^>]+>/).size
  end

  def render_and_convert requested_backend
    FileUtils.mkdir_p(results_dir)
    Dir.glob(File.join(results_dir, '*.meta.txt')).each { |path| File.delete(path) }

    html_path = File.join(results_dir, "kitchen-sink.#{requested_backend}.html")
    markdown_path = File.join(results_dir, "kitchen-sink.#{requested_backend}.md")

    result = described_class.mark_down_grade(
      fixture_path,
      markdown_path,
      html_output_path: html_path,
      backend: requested_backend,
      header_footer: false,
      include_frontmatter: true,
      markdown_options: { github_flavored: true },
      markdown_converter: Sourcerer::MarkDownGrade.method(:convert_html))

    yield result[:used_backend], result[:markdown], result[:frontmatter]
  end

  def collect_backend_results
    comparison = {}

    render_and_convert('html5') do |used_backend, markdown, frontmatter|
      comparison[:html5_backend] = used_backend
      comparison[:html5_markdown] = markdown
      comparison[:html5_frontmatter] = frontmatter
    end

    render_and_convert('asciidoctor-html5s') do |used_backend, markdown, frontmatter|
      comparison[:fallback_backend] = used_backend
      comparison[:fallback_markdown] = markdown
      comparison[:fallback_frontmatter] = frontmatter
    end

    comparison
  end

  def expect_shared_markdown_contract markdown:, frontmatter:
    expect(markdown.length).to be > 5000
    expect(frontmatter).to be_a(Hash)
    expect(frontmatter['computed-attr']).to eq('docs-layout')
    expect(markdown).to include("computed-attr: docs-layout\n")
    expect(markdown).to include('<dl>', '<a id="')
    expect(markdown).to match(/\(#anchor-1\)|href="#anchor-1"/)
    expect(markdown).to match(%r{\*\*NOTE:\*\*|<span class="title-label">Note: </span>})
  end

  def expect_fallback_semantic_contract markdown:
    forbidden = ['<section', '<nav', '* * *', '[1. Footnotes](#_footnotes)', '<aside class="sidebar">']
    expect(markdown).not_to include(*forbidden)
    expect(markdown).to include(
      '# AsciiDoc Kitchen Sink (Original Content)',
      '[Footnotes](#_footnotes)',
      'This document is an original “kitchen-sink” sample',
      '[[1]](#_footnote_1 "View footnote 1")',
      '<a id="_footnote_1"></a>',
      '**Optional title**',
      "\n---\n",
      '<!-- block::sidebar',
      '##### [SIDEBAR]',
      '<!-- end::sidebar -->',
      '<figure class="example-block">',
      '</figure>',
      "**Optional title**  \nA simple paragraph with an optional title.",
      "- bullet 2\n  - bullet 2a\n  - bullet 2b",
      "2. number\n  1. letter\n  2. letter",
      '<dl class="horizontal">',
      '<dl class="qanda">',
      '## 3. Notices',
      '```javascript')

    expected_figcaption =
      '<figcaption>**Example: Example block containing an admonition and a code listing**</figcaption>'
    expect(markdown).to include(expected_figcaption)
  end

  def expect_fallback_backend_contract comparison
    markdown = comparison.fetch(:fallback_markdown)
    html5_markdown = comparison.fetch(:html5_markdown)
    frontmatter = comparison.fetch(:fallback_frontmatter)
    backend = comparison.fetch(:fallback_backend)

    expect(backend).to match(/\Ahtml5s?\z/)
    expect_shared_markdown_contract(markdown: markdown, frontmatter: frontmatter)
    expect_fallback_semantic_contract(markdown: markdown)
    expect(markdown).not_to include('> This document is an original “kitchen-sink” sample')
    expect(html_tag_count(markdown)).to be <= html_tag_count(html5_markdown)
  end

  it 'downgrades traditional html5 output with expected semantic preservation' do
    render_and_convert('html5') do |backend, markdown, frontmatter|
      expect_html5_backend(backend, markdown, frontmatter)
    end
  end

  it 'downgrades semantic backend request output with fallback tolerance' do
    expect_fallback_backend_contract(collect_backend_results)
  end

  def expect_html5_backend used_backend, markdown, frontmatter
    expect(used_backend).to eq('html5')
    expect_shared_markdown_contract(markdown: markdown, frontmatter: frontmatter)
  end
end
