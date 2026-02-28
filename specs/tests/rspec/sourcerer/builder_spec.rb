# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../spec_helper'

RSpec.describe Sourcerer::Builder do
  let(:tmpdir) { Dir.mktmpdir }
  let(:generated_file) { File.join(tmpdir, 'generated', 'prebuild.rb') }
  let(:generated) { { path: generated_file, module: 'GeneratedSpec' } }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  before do
    allow(Sourcerer::AsciiDoc).to receive_messages(
      load_attributes: { 'site' => 'docs' },
      load_include: 'snippet output',
      extract_tagged_content: 'region output')
  end

  def run_prebuild **options
    FileUtils.mkdir_p(File.dirname(generated_file))
    Dir.chdir(tmpdir) { described_class.generate_prebuild(generated: generated, **options) }
  end

  describe '.generate_prebuild' do
    it 'writes the generated ruby module file' do
      run_prebuild
      expect(File.read(generated_file)).to include('module GeneratedSpec')
    end

    it 'writes snippet build output with default filename' do
      run_prebuild(snippets: [{ source: 'snip.adoc', tag: 'intro' }])
      expect(File.read(File.join(tmpdir, 'build/snippets/intro.txt'))).to eq('snippet output')
    end

    it 'writes region build output with default filename' do
      run_prebuild(regions: [{ source: 'region.adoc', tag: 'main' }])
      expect(File.read(File.join(tmpdir, 'build/regions/main.adoc'))).to eq('region output')
    end

    it 'writes named attributes into generated constants' do
      run_prebuild(attributes: [{ source: 'attrs.adoc', name: :doc }])
      expect(File.read(generated_file)).to include(':doc=>{"site"=>"docs"}')
    end

    it 'rejects unknown prebuild options' do
      expect { run_prebuild(unknown: true) }.to raise_error(ArgumentError, /unknown option/)
    end

    it 'rejects snippet entries missing :source' do
      expect { run_prebuild(snippets: [{ tag: 'intro' }]) }.to raise_error(ArgumentError, /missing :source/)
    end

    it 'rejects entries with both :tag and :tags' do
      entry = { source: 'snip.adoc', tag: 'intro', tags: ['intro'] }
      expect { run_prebuild(snippets: [entry]) }.to raise_error(ArgumentError, /only one of :tag or :tags/)
    end

    it 'rejects entries missing both :tag and :tags' do
      expect { run_prebuild(snippets: [{ source: 'snip.adoc' }]) }.to raise_error(ArgumentError, /must include a :tag/)
    end

    it 'rejects duplicate output names within a type' do
      entries = [{ source: 'a.adoc', tag: 'one', out: 'x.txt' }, { source: 'b.adoc', tag: 'two', out: 'x.txt' }]
      expect { run_prebuild(snippets: entries) }.to raise_error(ArgumentError, /out value must be unique/)
    end

    it 'accepts templates and render keys from config' do
      expect { run_prebuild(templates: [{ path: 'x' }], render: [{ out: 'y' }]) }.not_to raise_error
    end
  end
end
