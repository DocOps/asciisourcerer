# frozen_string_literal: true

require 'tmpdir'
require_relative '../spec_helper'

RSpec.describe Sourcerer::AsciiDoc do
  let(:fixture_path) { File.expand_path('../../fixtures/frontmatter-sample.adoc', __dir__) }
  let(:conversion) { perform_frontmatter_conversion(fixture_path) }
  let(:frontmatter) { conversion[:result][:frontmatter] }
  let(:html) { conversion[:html] }
  let(:markdown) { conversion[:markdown] }

  def perform_frontmatter_conversion fixture_path
    Dir.mktmpdir do |tmpdir|
      html_path = File.join(tmpdir, 'frontmatter-sample.html')
      markdown_path = File.join(tmpdir, 'frontmatter-sample.md')
      result = described_class.mark_down_grade(
        fixture_path,
        markdown_path,
        html_output_path: html_path,
        backend: 'html5',
        header_footer: false,
        include_frontmatter: true,
        markdown_options: { github_flavored: true },
        markdown_converter: Sourcerer::MarkDownGrade.method(:convert_html))

      {
        result: result,
        html: File.read(html_path),
        markdown: File.read(markdown_path)
      }
    end
  end

  it 'extracts layout into frontmatter' do
    expect(frontmatter['layout']).to eq('docs')
  end

  it 'extracts permalink into frontmatter' do
    expect(frontmatter['permalink']).to eq('/sample/frontmatter')
  end

  it 'extracts nav_order into frontmatter' do
    expect(frontmatter['nav_order']).to eq('9')
  end

  it 'extracts title into frontmatter' do
    expect(frontmatter['title']).to eq('Frontmatter Sample Page')
  end

  it 'strips page-* frontmatter source keys' do
    stripped_keys = %w[page-permalink page-nav_order page-title]
    expect(frontmatter.keys & stripped_keys).to be_empty
  end

  it 'prepends YAML frontmatter to rendered html output' do
    expect(html).to start_with("---\n")
  end

  it 'writes permalink in rendered html frontmatter' do
    expect(html).to match(%r{permalink:\s+"?/sample/frontmatter"?\n})
  end

  it 'prepends YAML frontmatter to rendered markdown output' do
    expect(markdown).to start_with("---\n")
  end

  it 'writes expected markdown frontmatter fields' do
    expect(markdown).to include("layout: docs\n", "title: Frontmatter Sample Page\n")
  end

  it 'writes a numeric nav_order field in markdown frontmatter' do
    expect(markdown).to match(/nav_order:\s+'?9'?/)
  end

  it 'preserves converted document content after frontmatter' do
    expected = 'A small AsciiDoc sample for frontmatter extraction tests.'
    expect(markdown).to include(expected)
  end
end
