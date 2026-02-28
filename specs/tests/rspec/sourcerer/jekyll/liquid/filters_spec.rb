# frozen_string_literal: true

require_relative '../../../spec_helper'

RSpec.describe Sourcerer::Jekyll::Liquid::Filters do
  let(:filter_host) do
    Class.new do
      include Liquid::StandardFilters
      include Sourcerer::Jekyll::Liquid::Filters
    end.new
  end

  def templated_field text
    Class.new do
      def initialize value
        @value = value
      end

      def templated?
        true
      end

      def render _scope = {}
        @value
      end
    end.new(text)
  end

  it 'renders plain Liquid input with vars' do
    rendered = filter_host.render('Hello {{ name }}', name: 'World')
    expect(rendered).to eq('Hello World')
  end

  it 'renders templated objects directly when available' do
    expect(filter_host.render(templated_field('templated text'))).to eq('templated text')
  end

  it 'sluggerizes strings in kebab format by default' do
    expect(filter_host.sluggerize('Hello World')).to eq('hello-world')
  end

  it 'sluggerizes strings in snake format' do
    expect(filter_host.sluggerize('Hello World', 'snake')).to eq('hello_world')
  end

  it 'inserts plus markers between paragraph breaks' do
    expect(filter_host.plusify("a\n\nb")).to eq("a\n+\nb")
  end

  it 'indents only non-first lines by default' do
    expect(filter_host.indent("one\ntwo", 2)).to eq("one\n  two")
  end

  it 'indents first line when line1 option is true' do
    expect(filter_host.indent("one\ntwo", 2, line1: true)).to eq("  one\n  two")
  end

  it 'returns the Ruby class name for values' do
    expect(filter_host.ruby_class(123)).to eq('Integer')
  end

  it 'title-cases words without hyphen support by default' do
    expect(filter_host.title_caps('hello world')).to eq('Hello World')
  end

  it 'removes basic markup punctuation' do
    expect(filter_host.demarkupify('`"quote"` and *bold*')).to eq('"quote" and bold')
  end

  it 'encodes and decodes base64 values' do
    encoded = filter_host.base64('hello')
    expect(filter_host.base64_decode(encoded)).to eq('hello')
  end

  it 'returns invalid base64 input unchanged on decode' do
    expect(filter_host.base64_decode('%%%invalid%%%')).to eq('%%%invalid%%%')
  end

  it 'encodes URL values' do
    expect(filter_host.url_encode('a b')).to eq('a+b')
  end

  it 'decodes URL values' do
    expect(filter_host.url_decode('a+b')).to eq('a b')
  end

  it 'escapes html values' do
    expect(filter_host.html_escape('<tag>')).to eq('&lt;tag&gt;')
  end

  it 'unescapes html values' do
    expect(filter_host.html_unescape('&lt;tag&gt;')).to eq('<tag>')
  end
end
