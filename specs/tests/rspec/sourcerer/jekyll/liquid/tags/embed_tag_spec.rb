# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'liquid'
require_relative '../../../../spec_helper'

RSpec.describe Sourcerer::Jekyll::Liquid::Tags::EmbedTag do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write_partial content
    path = File.join(tmpdir, 'partial.liquid')
    File.write(path, content)
    path
  end

  def render_embed markup:, vars: {}, registers: { includes_load_paths: [tmpdir] }
    Liquid::Template.register_tag('embed', described_class)
    template = Liquid::Template.parse("{% embed #{markup} %}")
    template.render!(vars, registers: registers)
  end

  it 'renders embedded partial content with context values' do
    write_partial('Hello {{ name }}')
    expect(render_embed(markup: 'partial.liquid', vars: { 'name' => 'World' })).to eq('Hello World')
  end

  it 'raises an error when the embed file is missing' do
    expect { render_embed(markup: 'missing.liquid') }.to raise_error(RuntimeError, /Embed file not found/)
  end

  it 'accepts a double-quoted partial name' do
    write_partial('Hello {{ name }}')
    expect(render_embed(markup: '"partial.liquid"', vars: { 'name' => 'World' })).to eq('Hello World')
  end

  it 'accepts a single-quoted partial name' do
    write_partial('Hello {{ name }}')
    expect(render_embed(markup: "'partial.liquid'", vars: { 'name' => 'World' })).to eq('Hello World')
  end

  it 'falls back to registers[:site].config["includes_load_paths"] when the direct register is absent' do
    write_partial('Hello {{ name }}')
    fake_site = instance_double(Jekyll::Site, config: { 'includes_load_paths' => [tmpdir] })
    result = render_embed(markup: 'partial.liquid', vars: { 'name' => 'World' }, registers: { site: fake_site })
    expect(result).to eq('Hello World')
  end
end
