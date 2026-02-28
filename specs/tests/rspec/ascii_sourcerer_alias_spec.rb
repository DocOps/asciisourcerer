# frozen_string_literal: true

require_relative 'spec_helper'
require 'asciisourcerer'

RSpec.describe AsciiSourcerer do
  context 'when used as module alias' do
    it 'provides VERSION through both namespaces' do
      expect(AsciiSourcerer::VERSION).to eq(Sourcerer::VERSION)
      expect(AsciiSourcerer::VERSION).to match(/^\d+\.\d+\.\d+/)
    end

    it 'provides access to AsciiDoc module' do
      expect(AsciiSourcerer::AsciiDoc).to eq(Sourcerer::AsciiDoc)
    end

    it 'provides access to Yaml module' do
      expect(AsciiSourcerer::Yaml).to eq(Sourcerer::Yaml)
    end

    it 'provides access to Rendering module' do
      expect(AsciiSourcerer::Rendering).to eq(Sourcerer::Rendering)
    end

    it 'provides access to Builder module' do
      expect(AsciiSourcerer::Builder).to eq(Sourcerer::Builder)
    end

    it 'provides access to MarkDownGrade module' do
      expect(AsciiSourcerer::MarkDownGrade).to eq(Sourcerer::MarkDownGrade)
    end

    it 'provides access to Jekyll module via autoload' do
      expect(AsciiSourcerer::Jekyll).to eq(Sourcerer::Jekyll)
    end
  end

  context 'when delegating methods' do
    it 'delegates class methods transparently' do
      # Test deprecated top-level method delegation through both namespaces
      readme_path = File.expand_path('../../../README.adoc', __dir__)

      sourcerer_attrs = Sourcerer.load_attributes(readme_path)
      asciisourcerer_attrs = described_class.load_attributes(readme_path)

      expect(asciisourcerer_attrs).to eq(sourcerer_attrs)
      expect(asciisourcerer_attrs['this_prod_vrsn']).to eq('0.1.0')
    end
  end

  context 'when using interchangeably' do
    it 'allows interchangeable use of both namespaces' do
      # Verify that code can use either namespace without issue
      expect { AsciiSourcerer::AsciiDoc }.not_to raise_error
      expect { Sourcerer::AsciiDoc }.not_to raise_error

      # Both should resolve to the same constant
      expect(AsciiSourcerer::AsciiDoc.object_id).to eq(Sourcerer::AsciiDoc.object_id)
    end
  end
end
