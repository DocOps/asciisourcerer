# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Sourcerer::Templating do
  def compile_fields data:, fields:, schema: nil, scope: {}, templating_config: nil
    described_class.compile_templated_fields!(
      data: data,
      fields: fields,
      schema: schema,
      scope: scope,
      templating_config: templating_config)
    data
  end

  def build_templated_field raw:, engine:, tagged:, inferred:
    compiled = described_class::Engines.compile(raw, engine)
    described_class::TemplatedField.new(raw, compiled, engine, tagged, inferred)
  end

  describe 'Engines' do
    let(:engines) { described_class::Engines }

    it 'compiles Liquid templates' do
      expect(engines.compile('Hello {{ name }}', 'liquid')).to be_a(Liquid::Template)
    end

    it 'compiles ERB templates' do
      expect(engines.compile('Hello <%= name %>', 'erb')).to be_a(ERB)
    end

    it 'raises for unsupported engines' do
      expect { engines.compile('x', 'mustache') }.to raise_error(ArgumentError, /Unsupported engine/)
    end

    it 'renders Liquid templates with variables' do
      compiled = engines.compile('Hello {{ name }}', 'liquid')
      expect(engines.render(compiled, 'liquid', { 'name' => 'World' })).to eq('Hello World')
    end

    it 'renders ERB templates with variables' do
      compiled = engines.compile('Hello <%= name %>', 'erb')
      expect(engines.render(compiled, 'erb', { name: 'World' })).to eq('Hello World')
    end
  end

  describe '.resolve_templating_config' do
    it 'returns callable config results' do
      config = -> { { 'default' => 'erb', 'delay' => true } }
      expect(described_class.resolve_templating_config(config)).to eq({ 'default' => 'erb', 'delay' => true })
    end

    it 'returns explicit hash config directly' do
      config = { 'default' => 'erb', 'delay' => true }
      expect(described_class.resolve_templating_config(config)).to eq(config)
    end

    it 'uses schema templating config when provided' do
      schema = { 'templating' => { 'default' => 'erb', 'delay' => true } }
      expect(described_class.resolve_templating_config(nil, schema: schema)).to eq(schema['templating'])
    end

    it 'falls back to default config when no source is provided' do
      expected = { 'default' => 'liquid', 'delay' => false }
      expect(described_class.resolve_templating_config(nil)).to eq(expected)
    end
  end

  describe '.compile_templated_fields!' do
    let(:fields) { [{ key: :title }] }

    it 'renders untagged Liquid fields using default engine' do
      data = { title: 'Hello {{ name }}' }
      compile_fields(data: data, fields: fields, scope: { 'name' => 'World' })
      expect(data[:title]).to eq('Hello World')
    end

    it 'honors tagged engine overrides' do
      data = { title: { '__tag__' => 'erb', 'value' => 'Hello <%= name %>' } }
      compile_fields(data: data, fields: fields, scope: { name: 'World' }, templating_config: { 'default' => 'liquid' })
      expect(data[:title]).to eq('Hello World')
    end

    it 'returns templated fields when delay is enabled' do
      data = { title: 'Hello {{ name }}' }
      compile_fields(data: data, fields: fields, templating_config: { 'default' => 'liquid', 'delay' => true })
      expect(data[:title]).to be_a(described_class::TemplatedField)
    end

    it 'skips non-templated values' do
      data = { title: 123 }
      compile_fields(data: data, fields: fields)
      expect(data[:title]).to eq(123)
    end

    it 'uses schema config when explicit config is omitted' do
      data = { title: 'Hello <%= name %>' }
      schema = { 'templating' => { 'default' => 'erb', 'delay' => false } }
      compile_fields(data: data, fields: fields, schema: schema, scope: { name: 'World' })
      expect(data[:title]).to eq('Hello World')
    end
  end

  describe '.render_field_if_template' do
    it 'renders templated field values' do
      field = build_templated_field(raw: 'Hello {{ name }}', engine: 'liquid', tagged: false, inferred: true)
      expect(described_class.render_field_if_template(field, { 'name' => 'World' })).to eq('Hello World')
    end

    it 'returns non-templated values unchanged' do
      expect(described_class.render_field_if_template('plain')).to eq('plain')
    end
  end

  describe 'TemplatedField' do
    it 'reports templated status' do
      field = build_templated_field(raw: 'x', engine: 'liquid', tagged: false, inferred: true)
      expect(field.templated?).to be(true)
    end

    it 'reports deferred status when compiled template is missing' do
      field = described_class::TemplatedField.new('x', nil, 'liquid', false, true)
      expect(field.deferred?).to be(true)
    end

    it 'returns self from to_liquid' do
      field = build_templated_field(raw: 'x', engine: 'liquid', tagged: false, inferred: true)
      expect(field.to_liquid).to be(field)
    end

    it 'supports Liquid context objects in render' do
      field = build_templated_field(raw: 'Hello {{ name }}', engine: 'liquid', tagged: false, inferred: true)
      context = instance_double(Liquid::Context, environments: [{ 'name' => 'World' }])
      expect(field.render(context)).to eq('Hello World')
    end
  end

  describe 'Context' do
    it 'builds context from schema settings' do
      schema = { 'templating' => { 'stage' => 'render', 'strict' => true, 'scopes' => { 'a' => { 'x' => 1 } } } }
      expect(described_class::Context.from_schema(schema)).to be_a(described_class::Context)
    end

    it 'normalizes stage to symbol from schema' do
      schema = { 'templating' => { 'stage' => 'render' } }
      expect(described_class::Context.from_schema(schema).stage).to eq(:render)
    end

    it 'normalizes scope keys to symbols' do
      schema = { 'templating' => { 'scopes' => { 'release' => { 'x' => 1 } } } }
      expect(described_class::Context.from_schema(schema).scopes.keys).to eq([:release])
    end

    it 'merges scopes into one hash' do
      context = described_class::Context.new(scopes: { one: { 'a' => 1 }, two: { 'b' => 2 } })
      expect(context.merged_scope).to eq({ 'a' => 1, 'b' => 2 })
    end
  end
end
