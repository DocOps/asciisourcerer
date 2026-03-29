# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../../../lib/asciidoctor/extensions/source-skim-tree-processor/extension'

RSpec.describe Sourcerer::SourceSkim do
  let(:fixture_path) { File.expand_path('../../fixtures/source-skim-sample.adoc', __dir__) }
  let(:skim)         { described_class.skim_file(fixture_path) }
  # Skim with all categories enabled, including opt-in ones (admonitions, quotes, attributes_builtin).
  let(:full_skim)    { described_class.skim_file(fixture_path, categories: Sourcerer::SourceSkim::ALL_CATEGORIES) }

  # ---------------------------------------------------------------------------
  describe '.skim_file' do
    it 'returns a Hash' do
      expect(skim).to be_a(Hash)
    end

    # -- document-level fields ------------------------------------------------
    describe 'document-level fields' do
      it 'includes the document title' do
        expect(skim[:title]).to eq('SourceSkim Sample Document')
      end

      it 'includes the source line count as a positive integer' do
        expect(skim[:lines]).to be_a(Integer)
        expect(skim[:lines]).to be_positive
      end

      it 'includes author-defined attributes' do
        expect(skim[:attributes_custom]).to include('custom-attr' => 'test-value')
        expect(skim[:attributes_custom]).to include('project-version' => '1.0.0')
      end

      it 'excludes Asciidoctor built-ins from attributes_custom' do
        expect(skim[:attributes_custom]).not_to have_key('doctype')
        expect(skim[:attributes_custom]).not_to have_key('asciidoctor-version')
        expect(skim[:attributes_custom]).not_to have_key('filetype')
      end

      it 'does not emit attributes_builtin by default' do
        expect(skim).not_to have_key(:attributes_builtin)
      end
    end

    # -- sections_tree --------------------------------------------------------
    describe 'sections_tree' do
      subject(:tree) { skim[:sections_tree] }

      it 'returns an array of root-level sections' do
        expect(tree).to be_an(Array)
        expect(tree.size).to eq(3)
      end

      it 'populates id, text, and level on each section' do
        alpha = tree.first
        expect(alpha[:id]).to eq('section-alpha')
        expect(alpha[:text]).to eq('Section Alpha')
        expect(alpha[:level]).to eq(1)
      end

      it 'records starts_at and ends_near as integers' do
        alpha = tree.first
        expect(alpha[:starts_at]).to be_a(Integer)
        expect(alpha[:ends_near]).to be_a(Integer)
        expect(alpha[:ends_near]).to be >= alpha[:starts_at]
      end

      it 'nests child sections under their parent' do
        alpha = tree.first
        expect(alpha[:sections]).to be_an(Array)
        expect(alpha[:sections].size).to eq(1)
        sub = alpha[:sections].first
        expect(sub[:id]).to eq('section-alpha-sub')
        expect(sub[:level]).to eq(2)
      end

      it 'uses an empty array for leaf-node sections' do
        beta = tree.last
        expect(beta[:sections]).to eq([])
      end
    end

    # -- sections_flat --------------------------------------------------------
    describe 'sections_flat' do
      subject(:flat) { described_class.skim_file(fixture_path, forms: [:flat])[:sections_flat] }

      it 'returns every section in a flat array' do
        expect(flat).to be_an(Array)
        expect(flat.size).to eq(4)
      end

      it 'sets parent_id to nil for root sections' do
        roots = flat.select { |s| s[:level] == 1 }
        expect(roots).to all(include(parent_id: nil))
      end

      it 'sets parent_id correctly for child sections' do
        child = flat.find { |s| s[:id] == 'section-alpha-sub' }
        expect(child[:parent_id]).to eq('section-alpha')
      end

      it 'lists child IDs in sections field' do
        alpha = flat.find { |s| s[:id] == 'section-alpha' }
        expect(alpha[:sections]).to eq(['section-alpha-sub'])
      end

      it 'uses an empty array for leaf sections field' do
        beta = flat.find { |s| s[:id] == 'section-beta' }
        expect(beta[:sections]).to eq([])
      end
    end

    # -- code_blocks ----------------------------------------------------------
    describe 'code_blocks' do
      subject(:blocks) { skim[:code_blocks] }

      it 'captures titled source blocks' do
        ruby_block = blocks.find { |b| b[:title] == 'Hello World in Ruby' }
        expect(ruby_block).not_to be_nil
        expect(ruby_block[:language]).to eq('ruby')
        expect(ruby_block[:starts_at]).to be_a(Integer)
        expect(ruby_block[:section_id]).to eq('section-beta')
      end

      it 'populates includes as an array' do
        ruby_block = blocks.find { |b| b[:title] == 'Hello World in Ruby' }
        expect(ruby_block[:includes]).to be_an(Array)
      end
    end

    # -- literal_blocks -------------------------------------------------------
    describe 'literal_blocks' do
      it 'captures titled literal blocks' do
        literal = skim[:literal_blocks].find { |b| b[:title] == 'Example Literal Output' }
        expect(literal).not_to be_nil
        expect(literal[:starts_at]).to be_a(Integer)
        expect(literal[:includes]).to be_an(Array)
      end
    end

    # -- definition_lists -----------------------------------------------------
    describe 'definition_lists' do
      it 'captures all definition lists regardless of title' do
        expect(skim[:definition_lists]).not_to be_empty
      end

      it 'captures the titled glossary with its terms' do
        glossary = skim[:definition_lists].find { |d| d[:title] == 'Glossary' }
        expect(glossary).not_to be_nil
        terms = glossary[:definition_terms].map { |t| t[:text] }
        expect(terms).to include('terminology', 'runtime')
      end

      it 'provides starts_at for each definition term' do
        glossary = skim[:definition_lists].find { |d| d[:title] == 'Glossary' }
        glossary[:definition_terms].each do |term|
          expect(term[:starts_at]).to be_a(Integer)
        end
      end
    end

    # -- examples -------------------------------------------------------------
    describe 'examples' do
      it 'captures titled example blocks' do
        example = skim[:examples].find { |e| e[:title] == 'Sample Example' }
        expect(example).not_to be_nil
        expect(example[:includes]).to be_an(Array)
      end
    end

    # -- sidebars -------------------------------------------------------------
    describe 'sidebars' do
      it 'captures titled sidebar blocks' do
        sidebar = skim[:sidebars].find { |s| s[:title] == 'Important Sidebar' }
        expect(sidebar).not_to be_nil
        expect(sidebar[:includes]).to be_an(Array)
      end
    end

    # -- tables ---------------------------------------------------------------
    describe 'tables' do
      it 'captures titled tables and their header cells' do
        table = skim[:tables].find { |t| t[:title] == 'Feature Matrix' }
        expect(table).not_to be_nil
        expect(table[:headers]).to eq(%w[Feature Status])
      end
    end

    # -- admonitions ----------------------------------------------------------
    describe 'admonitions' do
      it 'does not emit admonitions in the default skim' do
        expect(skim).not_to have_key(:admonitions)
      end

      it 'captures titled admonitions when the category is requested' do
        tip = full_skim[:admonitions].find { |a| a[:title] == 'Helpful Tip' }
        expect(tip).not_to be_nil
        expect(tip[:type]).to eq('TIP')
      end

      it 'does not capture untitled admonitions even when the category is requested' do
        expect(full_skim[:admonitions].map { |a| a[:title] }).to all(be_a(String))
      end
    end

    # -- quotes ---------------------------------------------------------------
    describe 'quotes' do
      it 'does not emit quotes in the default skim' do
        expect(skim).not_to have_key(:quotes)
      end

      it 'captures titled quote blocks with attribution when the category is requested' do
        quote = full_skim[:quotes].find { |q| q[:title] == 'Words of Wisdom' }
        expect(quote).not_to be_nil
        expect(quote[:attribution]).to eq('DocOps Lab')
      end

      it 'does not capture quotes with neither title nor attribution' do
        untitled = full_skim[:quotes].find { |q| !q[:title] && !q[:attribution] }
        expect(untitled).to be_nil
      end
    end

    # -- negative cases -------------------------------------------------------
    describe 'negative cases' do
      it 'does not capture untitled listing blocks' do
        expect(skim[:code_blocks].map { |b| b[:title] }).to all(be_a(String))
      end

      it 'does not capture untitled literal blocks' do
        expect(skim[:literal_blocks].map { |b| b[:title] }).to all(be_a(String))
      end

      it 'does not capture untitled example blocks' do
        expect(skim[:examples].map { |b| b[:title] }).to all(be_a(String))
      end

      it 'does not capture untitled sidebar blocks' do
        expect(skim[:sidebars].map { |b| b[:title] }).to all(be_a(String))
      end

      it 'does not capture a table with no title and no header row' do
        headerless_titleless = skim[:tables].find { |t| !t[:title] && !t.key?(:headers) }
        expect(headerless_titleless).to be_nil
      end
    end

    # -- images ---------------------------------------------------------------
    describe 'images' do
      it 'captures image blocks with target and alt' do
        img = skim[:images].find { |i| i[:target] == 'docs/diagram.png' }
        expect(img).not_to be_nil
        expect(img[:title]).to eq('System Diagram')
        expect(img[:alt]).to eq('System architecture diagram')
        expect(img[:starts_at]).to be_a(Integer)
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe '.skim_string' do
    let(:content) do
      <<~ADOC
        = String Test
        :my-attr: hello

        [#one]
        == One Section

        Some content.

        .A Code Block
        [source,bash]
        ----
        echo hello
        ----
      ADOC
    end

    it 'skims inline AsciiDoc content' do
      result = described_class.skim_string(content)
      expect(result[:title]).to eq('String Test')
      expect(result[:attributes_custom]).to include('my-attr' => 'hello')
      expect(result[:sections_tree].first[:text]).to eq('One Section')
    end

    it 'captures code blocks from a string skim' do
      result = described_class.skim_string(content)
      code   = result[:code_blocks].find { |b| b[:title] == 'A Code Block' }
      expect(code).not_to be_nil
      expect(code[:language]).to eq('bash')
    end
  end

  # ---------------------------------------------------------------------------
  describe 'configuration' do
    describe 'forms: [:tree, :flat]' do
      it 'emits both section shapes' do
        result = described_class.skim_file(fixture_path, forms: %i[tree flat])
        expect(result).to have_key(:sections_tree)
        expect(result).to have_key(:sections_flat)
      end
    end

    describe 'forms: []' do
      it 'emits no section keys' do
        result = described_class.skim_file(fixture_path, forms: [])
        expect(result).not_to have_key(:sections_tree)
        expect(result).not_to have_key(:sections_flat)
      end
    end

    describe 'categories: [:code_blocks]' do
      it 'emits only the requested category' do
        result = described_class.skim_file(fixture_path, forms: [], categories: [:code_blocks])
        expect(result).to have_key(:code_blocks)
        expect(result).not_to have_key(:definition_lists)
        expect(result).not_to have_key(:tables)
        expect(result).not_to have_key(:attributes_custom)
      end
    end

    describe 'categories: [:attributes_builtin]' do
      it 'emits attributes_builtin when explicitly requested' do
        result = described_class.skim_file(fixture_path, categories: [:attributes_builtin])
        expect(result).to have_key(:attributes_builtin)
        expect(result[:attributes_builtin]).to have_key('doctype')
      end

      it 'does not emit attributes_custom when not in categories' do
        result = described_class.skim_file(fixture_path, categories: [:attributes_builtin])
        expect(result).not_to have_key(:attributes_custom)
      end
    end

    describe 'attributes: overrides' do
      it 'makes caller-supplied attributes visible in the parsed document' do
        result = described_class.skim_file(
          fixture_path,
          categories: [:attributes_custom],
          attributes: { 'injected-env' => 'ci' })
        expect(result[:attributes_custom]).to include('injected-env' => 'ci')
      end

      it 'accepts attribute overrides in skim_string too' do
        content = "= Override Test\n\n== One Section\n\nContent.\n"
        result = described_class.skim_string(
          content,
          categories: [:attributes_custom],
          attributes: { 'build-env' => 'test' })
        expect(result[:attributes_custom]).to include('build-env' => 'test')
      end

      it 'does not mutate LOAD_OPTS attributes' do
        described_class.skim_file(fixture_path, attributes: { 'x' => 'y' })
        expect(Sourcerer::SourceSkim::LOAD_OPTS[:attributes]).not_to have_key('x')
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe Sourcerer::SourceSkim::TreeProcessorExtension do
    it 'is a subclass of Asciidoctor::Extensions::TreeProcessor' do
      expect(described_class.ancestors).to include(Asciidoctor::Extensions::TreeProcessor)
    end

    it 'stores the skim hash as a document attribute' do
      content = "= Extension Test\n\n[#sec]\n== A Section\n\nContent.\n"
      klass = described_class
      doc     = Asciidoctor.load(
        content,
        safe:       :safe,
        sourcemap:  true,
        extensions: proc { tree_processor klass })
      skim = doc.attr('source-skim-result')
      expect(skim).to be_a(Hash)
      expect(skim[:title]).to eq('Extension Test')
      expect(skim[:sections_tree].first[:id]).to eq('sec')
    end

    it 'respects source-skim-forms document attribute' do
      content = ":source-skim-forms: flat\n\n= Forms Test\n\n== One\n\nContent.\n"
      klass = described_class
      doc     = Asciidoctor.load(
        content,
        safe:       :safe,
        sourcemap:  true,
        extensions: proc { tree_processor klass })
      skim = doc.attr('source-skim-result')
      expect(skim).to have_key(:sections_flat)
      expect(skim).not_to have_key(:sections_tree)
    end
  end
end
