# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Sourcerer do
  describe 'namespace surface' do
    it 'exposes dedicated modules for AsciiDoc and rendering workflows' do
      expect(described_class.constants).to include(:AsciiDoc, :Rendering, :Yaml)
    end
  end

  describe 'compatibility delegators' do
    it 'delegates AsciiDoc methods to Sourcerer::AsciiDoc' do
      allow(Sourcerer::AsciiDoc).to receive(:load_attributes).with('sample.adoc').and_return({ 'a' => 'b' })
      expect(described_class.load_attributes('sample.adoc')).to eq({ 'a' => 'b' })
    end

    it 'delegates rendering methods to Sourcerer::Rendering' do
      render_entry = { data: 'in.yml', out: 'out.txt', converter: ->(data, _entry) { data.inspect } }
      allow(Sourcerer::Rendering).to receive(:render_with_converter).with(render_entry).and_return(nil)

      described_class.render_with_converter(render_entry)
      expect(Sourcerer::Rendering).to have_received(:render_with_converter).with(render_entry)
    end

    it 'returns values from rendering delegators' do
      render_entry = { data: 'in.yml', out: 'out.txt', converter: ->(data, _entry) { data.inspect } }
      allow(Sourcerer::Rendering).to receive(:render_with_converter).with(render_entry).and_return('rendered')

      expect(described_class.render_with_converter(render_entry)).to eq('rendered')
    end
  end
end
