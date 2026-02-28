# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Sourcerer::Jekyll do
  before do
    allow(described_class::Bootstrapper).to receive(:load_plugins)
    allow(described_class::Monkeypatches).to receive(:patch_jekyll)
    allow(Liquid::Template).to receive(:register_filter)
    allow(Liquid::Template).to receive(:register_tag)
    described_class.initialize_liquid_runtime
  end

  it 'loads plugins before rendering' do
    expect(described_class::Bootstrapper).to have_received(:load_plugins)
  end

  it 'applies monkeypatches before rendering' do
    expect(described_class::Monkeypatches).to have_received(:patch_jekyll)
  end

  it 'registers Sourcerer Liquid filters' do
    expect(Liquid::Template).to have_received(:register_filter).with(described_class::Liquid::Filters)
  end

  it 'registers Jekyll core filters' do
    expect(Liquid::Template).to have_received(:register_filter).with(Jekyll::Filters)
  end

  it 'registers jekyll-asciidoc filters' do
    expect(Liquid::Template).to have_received(:register_filter).with(Jekyll::AsciiDoc::Filters)
  end

  it 'registers embed tag under sourcerer tags namespace' do
    expected = described_class::Liquid::Tags::EmbedTag
    expect(Liquid::Template).to have_received(:register_tag).with('embed', expected)
  end
end
