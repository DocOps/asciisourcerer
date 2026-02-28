# frozen_string_literal: true

require 'asciidoctor'
require_relative '../spec_helper'

RSpec.describe Sourcerer::PlainTextConverter do
  let(:converter) { described_class.new('plaintext') }

  def node name, **stubs
    Object.new.tap do |obj|
      obj.define_singleton_method(:node_name) { name }
      stubs.each { |method_name, value| obj.define_singleton_method(method_name) { value } }
    end
  end

  def emit_attrs_output
    doc = Asciidoctor.load(
      '= Title',
      backend: 'plaintext',
      header_footer: false,
      attributes: { 'foo' => 'bar', 'sourcerer_mode' => 'emit_attrs' })
    converter.convert(doc)
  end

  it 'registers for the plaintext backend' do
    expect(Asciidoctor::Converter.for('plaintext')).to eq(described_class)
  end

  it 'converts section nodes with title and paragraph text' do
    paragraph = node('paragraph', lines: ['Body'])
    section = node('section', title?: true, title: 'Intro', blocks: [paragraph])
    expect(converter.convert(section)).to eq("Intro\nBody")
  end

  it 'converts listing nodes from content' do
    expect(converter.convert(node('listing', content: 'puts 1'))).to eq('puts 1')
  end

  it 'converts literal nodes from content' do
    expect(converter.convert(node('literal', content: 'verbatim'))).to eq('verbatim')
  end

  it 'falls back to node content when no typed converter exists' do
    expect(converter.convert(node('unknown', content: 'fallback content'))).to eq('fallback content')
  end

  it 'falls back to node text when content is unavailable' do
    expect(converter.convert(node('unknown', text: 'fallback text'))).to eq('fallback text')
  end

  it 'returns empty string when no fallback is available' do
    expect(converter.convert(node('unknown'))).to eq('')
  end

  it 'emits custom attributes in emit_attrs mode' do
    expect(emit_attrs_output).to include(':foo: bar')
  end

  it 'omits sourcerer_mode from emitted attributes' do
    expect(emit_attrs_output).not_to include(':sourcerer_mode:')
  end
end
