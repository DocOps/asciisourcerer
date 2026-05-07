# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../../../lib/sourcerer/sync/block_parser'

RSpec.describe Sourcerer::Sync::BlockParser do
  describe '.parse' do
    context 'with HTML/Markdown comment tags' do
      let(:text) do
        <<~MD
          # Header

          <!-- tag::universal-intro[] -->
          Intro content.
          Second intro line.
          <!-- end::universal-intro[] -->

          Local content.

          <!-- tag::universal-footer[] -->
          Footer content.
          <!-- end::universal-footer[] -->

          Tail text.
        MD
      end

      it 'returns segments in document order' do
        segments = described_class.parse(text)
        expect(segments).not_to be_empty
      end

      it 'identifies two Block segments' do
        blocks = described_class.parse(text).grep(described_class::Block)
        expect(blocks.map(&:tag)).to eq(%w[universal-intro universal-footer])
      end

      it 'preserves block content exactly' do
        intro = described_class.parse(text).find { |s| s.is_a?(described_class::Block) && s.tag == 'universal-intro' }
        expect(intro.content).to eq("Intro content.\nSecond intro line.\n")
      end

      it 'preserves open and close marker lines verbatim' do
        intro = described_class.parse(text).find { |s| s.is_a?(described_class::Block) && s.tag == 'universal-intro' }
        expect(intro.open_line).to eq("<!-- tag::universal-intro[] -->\n")
        expect(intro.close_line).to eq("<!-- end::universal-intro[] -->\n")
      end

      it 'reconstructs the original text losslessly' do
        segments = described_class.parse(text)
        reconstructed = segments.map do |s|
          s.is_a?(described_class::Block) ? "#{s.open_line}#{s.content}#{s.close_line}" : s.content
        end.join
        expect(reconstructed).to eq(text)
      end
    end

    context 'with AsciiDoc line-comment tags' do
      let(:text) do
        <<~ADOC
          = Title

          // tag::universal-intro[]
          Intro paragraph.
          // end::universal-intro[]

          Local section.
        ADOC
      end

      it 'parses the block correctly' do
        blocks = described_class.parse(text).grep(described_class::Block)
        expect(blocks.size).to eq(1)
        expect(blocks.first.tag).to eq('universal-intro')
        expect(blocks.first.content).to eq("Intro paragraph.\n")
      end

      it 'reconstructs the original text losslessly' do
        segments = described_class.parse(text)
        reconstructed = segments.map do |s|
          s.is_a?(described_class::Block) ? "#{s.open_line}#{s.content}#{s.close_line}" : s.content
        end.join
        expect(reconstructed).to eq(text)
      end
    end

    context 'with shell/Ruby comment tags' do
      let(:text) do
        "# tag::universal-config[]\nsome: yaml\n# end::universal-config[]\n"
      end

      it 'parses the block' do
        blocks = described_class.parse(text).grep(described_class::Block)
        expect(blocks.size).to eq(1)
        expect(blocks.first.tag).to eq('universal-config')
        expect(blocks.first.content).to eq("some: yaml\n")
      end
    end

    context 'with tags that omit the trailing []' do
      let(:text) do
        <<~MD
          <!-- tag::universal-approach -->
          Approach content.
          <!-- end::universal-approach[] -->
        MD
      end

      it 'parses the block despite the missing []' do
        blocks = described_class.parse(text).grep(described_class::Block)
        expect(blocks.size).to eq(1)
        expect(blocks.first.tag).to eq('universal-approach')
      end
    end

    context 'with no tags' do
      let(:text) { "Just plain text.\nNo blocks here.\n" }

      it 'returns a single TextSegment' do
        segments = described_class.parse(text)
        expect(segments.size).to eq(1)
        expect(segments.first).to be_a(described_class::TextSegment)
        expect(segments.first.content).to eq(text)
      end
    end

    context 'with empty input' do
      it 'returns an empty array' do
        expect(described_class.parse('')).to eq([])
      end
    end

    context 'with only a non-canonical block' do
      let(:text) do
        <<~MD
          <!-- tag::local-notes[] -->
          Local project notes.
          <!-- end::local-notes[] -->
        MD
      end

      it 'treats the non-canonical block markers as plain text' do
        segments = described_class.parse(text)
        expect(segments).to all(be_a(described_class::TextSegment))
      end

      it 'reconstructs the original text losslessly' do
        segments = described_class.parse(text)
        reconstructed = segments.map(&:content).join
        expect(reconstructed).to eq(text)
      end
    end

    context 'with inner tags treated as content' do
      let(:text) do
        <<~MD
          <!-- tag::universal-outer[] -->
          // tag::inner-block[]
          nested content
          // end::inner-block[]
          <!-- end::universal-outer[] -->
        MD
      end

      it 'treats inner tags as block content' do
        blocks = described_class.parse(text).grep(described_class::Block)
        expect(blocks.size).to eq(1)
        expect(blocks.first.tag).to eq('universal-outer')
        expect(blocks.first.content).to include('// tag::inner-block[]')
        expect(blocks.first.content).to include('nested content')
      end
    end

    context 'when error conditions occur' do
      it 'raises ParseError for an unclosed canonical tag' do
        text = "<!-- tag::universal-intro[] -->\nno closing tag\n"
        expect { described_class.parse(text) }.to raise_error(described_class::ParseError, /Unclosed canonical tag/)
      end
    end
  end

  describe '.extract_canonical' do
    let(:text) do
      <<~MD
        <!-- tag::universal-intro[] -->
        Intro.
        <!-- end::universal-intro[] -->
      MD
    end

    it 'returns canonical blocks as a hash keyed by tag name' do
      segments = described_class.parse(text)
      canonical = described_class.extract_canonical(segments)
      expect(canonical.keys).to eq(['universal-intro'])
      expect(canonical['universal-intro']).to be_a(described_class::Block)
    end

    it 'raises ParseError on duplicate canonical blocks' do
      dup_text = <<~MD
        <!-- tag::universal-intro[] -->
        First.
        <!-- end::universal-intro[] -->
        <!-- tag::universal-intro[] -->
        Second.
        <!-- end::universal-intro[] -->
      MD
      segments = described_class.parse(dup_text)
      expect { described_class.extract_canonical(segments) }.to raise_error(described_class::ParseError, /Duplicate/)
    end

    it 'respects a custom canonical_prefix' do
      local_text = <<~MD
        <!-- tag::local-notes[] -->
        Notes.
        <!-- end::local-notes[] -->
      MD
      segments = described_class.parse(local_text, canonical_prefix: 'local-')
      canonical = described_class.extract_canonical(segments, canonical_prefix: 'local-')
      expect(canonical.keys).to eq(['local-notes'])
    end
  end
end
