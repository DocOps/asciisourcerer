# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../../../spec_helper'

RSpec.describe Sourcerer::Jekyll::Liquid::FileSystem do
  let(:tmpdir) { Dir.mktmpdir }
  let(:root_a) { File.join(tmpdir, 'a') }
  let(:root_b) { File.join(tmpdir, 'b') }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write_template root, rel_path, content
    path = File.join(root, rel_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  it 'resolves files from a single root' do
    expected = write_template(root_a, 'includes/demo.liquid', 'hello')
    fs = described_class.new(root_a)
    expect(fs.full_path('includes/demo.liquid')).to eq(File.expand_path(expected))
  end

  it 'reads file content via read_template_file' do
    write_template(root_a, 'parts/a.liquid', 'sample')
    fs = described_class.new(root_a)
    expect(fs.read_template_file('parts/a.liquid')).to eq('sample')
  end

  it 'rejects traversal outside a single root' do
    fs = described_class.new(root_a)
    expect { fs.full_path('../secrets.txt') }.to raise_error(Liquid::FileSystemError, /Illegal template path/)
  end

  it 'resolves files from the first matching root in multi-root mode' do
    write_template(root_b, 'shared/header.liquid', 'from-b')
    fs = described_class.new([root_a, root_b])
    expect(fs.full_path('shared/header.liquid')).to eq(File.expand_path(File.join(root_b, 'shared/header.liquid')))
  end

  it 'raises when a template is missing in multi-root mode' do
    fs = described_class.new([root_a, root_b])
    expect { fs.full_path('missing.liquid') }.to raise_error(Liquid::FileSystemError, /Template not found/)
  end
end
