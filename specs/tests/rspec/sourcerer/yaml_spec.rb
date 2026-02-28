# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Sourcerer::Yaml do
  describe 'tag helpers' do
    let(:tagged) { { 'value' => 'abc', '__tag__' => 'erb' } }

    it 'detags tagged values' do
      expect(described_class::TagUtils.detag(tagged)).to eq('abc')
    end

    it 'leaves untagged values unchanged during detagging' do
      expect(described_class::TagUtils.detag('abc')).to eq('abc')
    end

    it 'returns a tag for tagged wrappers' do
      expect(described_class::TagUtils.tag_of(tagged)).to eq('erb')
    end

    it 'returns nil for non-tagged values when requesting a tag' do
      expect(described_class::TagUtils.tag_of('abc')).to be_nil
    end

    it 'detects matching tags' do
      expect(described_class::TagUtils.tag?(tagged, :erb)).to be(true)
    end

    it 'rejects non-matching tags' do
      expect(described_class::TagUtils.tag?(tagged, 'liquid')).to be(false)
    end
  end

  describe '.load_with_tags' do
    let(:path) { File.expand_path('../../fixtures/yaml-with-tags.yml', __dir__) }
    let(:data) { described_class.load_with_tags(path) }

    it 'preserves YAML tags on top-level string values' do
      tagged = { 'value' => '{{ release.name }}', '__tag__' => 'liquid' }
      expect(data['title']).to eq(tagged)
    end

    it 'preserves YAML tags on nested string values' do
      tagged = { 'value' => "<%= File.join('a', 'b') %>", '__tag__' => 'erb' }
      expect(data.dig('nested', 'path')).to eq(tagged)
    end
  end

  describe '.load_with_attributes' do
    it 'resolves AsciiDoc attribute references in dflt values' do
      path = File.expand_path('../../fixtures/yaml-with-attrs.yml', __dir__)
      attrs = { 'default_markup' => 'markdown' }
      data = described_class.load_with_attributes(path, attrs)

      expect(data['properties']['$meta']['properties']['markup']['dflt']).to eq('markdown')
    end

    it 'leaves attribute placeholders intact when no value is provided' do
      path = File.expand_path('../../fixtures/yaml-with-attrs.yml', __dir__)
      data = described_class.load_with_attributes(path, {})
      expect(data['properties']['$meta']['properties']['markup']['dflt']).to eq('{default_markup}')
    end
  end
end
