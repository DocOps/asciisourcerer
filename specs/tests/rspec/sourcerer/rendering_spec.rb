# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../spec_helper'

RSpec.describe Sourcerer::Rendering do
  let(:tmpdir) { Dir.mktmpdir }
  let(:data_file) { write_file('input.yml', "name: world\n") }
  let(:template_file) { write_file('template.erb', "<%= data['name'] %>") }
  let(:out_file) { File.join(tmpdir, 'out', 'rendered.txt') }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write_file rel_path, content
    path = File.join(tmpdir, rel_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def converter_entry converter:
    { data: data_file, out: out_file, converter: converter }
  end

  def expected_template_call template:, data:, out:
    [
      template,
      data,
      out,
      {
        data_object: 'data',
        attrs_source: nil,
        engine: 'liquid'
      }
    ]
  end

  describe '.render_template' do
    it 'renders erb output with default data object' do
      described_class.render_template(template_file, data_file, out_file, engine: 'erb')
      expect(File.read(out_file)).to eq('world')
    end

    it 'supports custom data_object names' do
      custom_template = write_file('release.erb', "<%= release['name'] %>")
      described_class.render_template(custom_template, data_file, out_file, engine: 'erb', data_object: 'release')
      expect(File.read(out_file)).to eq('world')
    end

    it 'rejects unknown options' do
      expect { described_class.render_template(template_file, data_file, out_file, engine: 'erb', unknown: true) }
        .to raise_error(ArgumentError, /unknown option/)
    end

    it 'rejects unsupported template engines' do
      expect { described_class.render_template(template_file, data_file, out_file, engine: 'mustache') }
        .to raise_error(ArgumentError, /Unsupported template engine/)
    end

    it 'loads data with attributes when attrs_source is given' do
      allow(Sourcerer::AsciiDoc).to receive(:load_attributes).and_return({ 'site' => 'docs' })
      allow(Sourcerer::Yaml).to receive(:load_with_attributes).and_return({ 'name' => 'attrs' })
      described_class.render_template(template_file, data_file, out_file, engine: 'erb', attrs_source: 'attrs.adoc')
      expect(Sourcerer::Yaml).to have_received(:load_with_attributes).with(data_file, { 'site' => 'docs' })
    end
  end

  describe '.render_outputs' do
    it 'returns nil for nil config' do
      expect(described_class.render_outputs(nil)).to be_nil
    end

    it 'delegates converter entries to render_with_converter' do
      entry = { converter: ->(_data, _entry) { 'ok' }, data: data_file, out: out_file }
      allow(described_class).to receive(:render_with_converter)
      described_class.render_outputs([entry])
      expect(described_class).to have_received(:render_with_converter).with(entry)
    end

    it 'delegates template entries to render_template with defaults' do
      entry = { template: template_file, data: data_file, out: out_file }
      allow(described_class).to receive(:render_template)
      described_class.render_outputs([entry])
      template, data, out, options = expected_template_call(template: template_file, data: data_file, out: out_file)
      expect(described_class).to have_received(:render_template).with(template, data, out, options)
    end
  end

  describe '.render_with_converter' do
    it 'writes converter output for callable converters' do
      converter = ->(data, _entry) { data.fetch('name').upcase }
      described_class.render_with_converter(converter_entry(converter: converter))
      expect(File.read(out_file)).to eq('WORLD')
    end

    it 'resolves converter constants by string name' do
      stub_const('SpecConverter', ->(data, _entry) { "#{data.fetch('name')}!" })
      described_class.render_with_converter(converter_entry(converter: 'SpecConverter'))
      expect(File.read(out_file)).to eq('world!')
    end

    it 'rejects entries missing :data' do
      expect { described_class.render_with_converter(out: out_file, converter: ->(_data, _entry) { 'x' }) }
        .to raise_error(ArgumentError, /missing :data/)
    end

    it 'rejects entries missing :out' do
      expect { described_class.render_with_converter(data: data_file, converter: ->(_data, _entry) { 'x' }) }
        .to raise_error(ArgumentError, /missing :out/)
    end

    it 'rejects converter output that is not a string' do
      converter = ->(_data, _entry) { { nope: true } }
      expect { described_class.render_with_converter(converter_entry(converter: converter)) }
        .to raise_error(ArgumentError, /non-string output/)
    end

    it 'rejects unsupported converter types' do
      expect { described_class.render_with_converter(converter_entry(converter: 42)) }
        .to raise_error(ArgumentError, /Unsupported converter/)
    end
  end
end
