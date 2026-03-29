# frozen_string_literal: true

require_relative '../spec_helper'
require 'tmpdir'

RSpec.describe Sourcerer::SourceSkim, 'Markdown format' do # rubocop:disable RSpec/DescribeMethod, RSpec/SpecFilePathFormat
  let(:fixtures_dir) { File.expand_path('../../fixtures', __dir__) }
  let(:md_fixture)   { File.join(fixtures_dir, 'frontmatter-reader-sample.md') }

  # fixture: # Introduction (title), ## Getting Started, ### Prerequisites, ## Advanced Usage

  # ---------------------------------------------------------------------------
  describe '.skim_file (default flat, auto-detected from .md extension)' do
    subject(:result) { described_class.skim_file(md_fixture) }

    it 'returns a Hash with title, frontmatter, and sections_flat keys' do
      expect(result).to include(:title, :frontmatter, :sections_flat)
    end

    it 'does not include sections_tree by default' do
      expect(result).not_to include(:sections_tree)
    end

    it 'extracts the H1 heading as the document title' do
      expect(result[:title]).to eq('Introduction')
    end

    describe 'frontmatter' do
      subject(:fm) { result[:frontmatter] }

      it 'returns a Hash' do
        expect(fm).to be_a(Hash)
      end

      it 'extracts layout' do
        expect(fm['layout']).to eq('docs')
      end

      it 'extracts title' do
        expect(fm['title']).to eq('Reader Sample')
      end

      it 'extracts nav_order (typed by YAML)' do
        expect(fm['nav_order']).to eq(3)
      end
    end

    describe 'sections_flat' do
      subject(:sections) { result[:sections_flat] }

      it 'returns an Array' do
        expect(sections).to be_an(Array)
      end

      it 'finds three sections (H1 is title, not a section)' do
        expect(sections.length).to eq(3)
      end

      it 'reads the H2 as level 1' do
        expect(sections[0]).to eq(text: 'Getting Started', level: 1, starts_at: 11)
      end

      it 'reads the H3 as level 2' do
        expect(sections[1]).to eq(text: 'Prerequisites', level: 2, starts_at: 15)
      end

      it 'reads the second H2 as level 1' do
        expect(sections[2]).to eq(text: 'Advanced Usage', level: 1, starts_at: 17)
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe '.skim_file with forms: [:tree]' do
    subject(:result) { described_class.skim_file(md_fixture, forms: [:tree]) }

    it 'returns a Hash with title, frontmatter, and sections_tree keys' do
      expect(result).to include(:title, :frontmatter, :sections_tree)
    end

    it 'does not include sections_flat' do
      expect(result).not_to include(:sections_flat)
    end

    describe 'sections_tree' do
      subject(:tree) { result[:sections_tree] }

      it 'is an Array (like AsciiDoc sections_tree)' do
        expect(tree).to be_an(Array)
      end

      it 'has two top-level (level 1) sections' do
        expect(tree.length).to eq(2)
        expect(tree[0][:text]).to eq('Getting Started')
        expect(tree[1][:text]).to eq('Advanced Usage')
      end

      it 'Getting Started is at level 1' do
        expect(tree[0][:level]).to eq(1)
        expect(tree[0][:starts_at]).to eq(11)
      end

      it 'nests Prerequisites (level 2) under Getting Started' do
        children = tree[0][:sections]
        expect(children.length).to eq(1)
        expect(children[0][:text]).to eq('Prerequisites')
        expect(children[0][:level]).to eq(2)
        expect(children[0][:starts_at]).to eq(15)
      end

      it 'Prerequisites has no nested children' do
        expect(tree[0][:sections][0][:sections]).to be_empty
      end

      it 'Advanced Usage has no children' do
        expect(tree[1][:sections]).to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe '.skim_file with forms: [:flat, :tree]' do
    subject(:result) { described_class.skim_file(md_fixture, forms: %i[flat tree]) }

    it 'includes both sections_flat and sections_tree' do
      expect(result).to include(:sections_flat, :sections_tree)
    end
  end

  # ---------------------------------------------------------------------------
  describe '.skim_file with no frontmatter' do
    subject(:result) do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'bare.md')
        File.write(path, "# Title\n\n## Sub\n")
        described_class.skim_file(path)
      end
    end

    it 'uses H1 as title' do
      expect(result[:title]).to eq('Title')
    end

    it 'returns empty frontmatter' do
      expect(result[:frontmatter]).to eq({})
    end

    it 'finds H2 as level 1 section' do
      expect(result[:sections_flat][0]).to eq(text: 'Sub', level: 1, starts_at: 3)
    end
  end

  # ---------------------------------------------------------------------------
  describe '.skim_file title falls back to frontmatter when no H1' do
    subject(:result) do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'no-h1.md')
        File.write(path, "---\ntitle: FM Title\n---\n\n## Section\n")
        described_class.skim_file(path)
      end
    end

    it 'falls back to frontmatter title' do
      expect(result[:title]).to eq('FM Title')
    end

    it 'treats ## as level 1 section' do
      expect(result[:sections_flat][0]).to eq(text: 'Section', level: 1, starts_at: 5)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'multiple H1 headings (only first consumed as title)' do
    subject(:result) do
      md = "# First Title\n\n## Section A\n\n# Second Title\n\n## Section B\n"
      described_class.skim_string(md, format: :markdown, forms: %i[flat tree])
    end

    it 'uses the first H1 as title' do
      expect(result[:title]).to eq('First Title')
    end

    it 'does not crash when a subsequent H1 appears (level 0 node)' do
      expect { result }.not_to raise_error
    end

    it 'places the subsequent H1 as a root-level entry in sections_tree' do
      titles = result[:sections_tree].map { |n| n[:text] }
      expect(titles).to include('Second Title')
    end
  end

  # ---------------------------------------------------------------------------
  describe '.skim_string with format: :markdown' do
    subject(:result) do
      described_class.skim_string("---\ntitle: Inline\n---\n\n# Hello\n", format: :markdown)
    end

    it 'uses H1 as title' do
      expect(result[:title]).to eq('Hello')
    end

    it 'retains frontmatter title in frontmatter hash' do
      expect(result[:frontmatter]['title']).to eq('Inline')
    end

    it 'has no sections (no ## headings)' do
      expect(result[:sections_flat]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  describe 'fenced code block exclusion' do
    subject(:result) do
      described_class.skim_string(md_with_fenced_comments, format: :markdown, forms: [:flat])
    end

    let(:md_with_fenced_comments) do
      <<~MD
        # Doc Title

        ## Real Section

        ```ruby
        # This is a Ruby comment, not a heading
        # Another comment
        def foo; end
        ```

        ## Another Real Section

        ~~~
        # Also not a heading
        ~~~
      MD
    end

    it 'does not treat fenced code block comment lines as headings' do
      texts = result[:sections_flat].map { |s| s[:text] }
      expect(texts).not_to include('This is a Ruby comment, not a heading')
      expect(texts).not_to include('Another comment')
      expect(texts).not_to include('Also not a heading')
    end

    it 'still captures real sections outside code blocks' do
      texts = result[:sections_flat].map { |s| s[:text] }
      expect(texts).to include('Real Section', 'Another Real Section')
    end
  end
end
