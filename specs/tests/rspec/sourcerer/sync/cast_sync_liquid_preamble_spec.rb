# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../../../lib/sourcerer/sync'
require 'tmpdir'

RSpec.describe Sourcerer::Sync::Cast, '#sync (liquid preamble)' do
  let(:prime_content) do
    <<~ADOC
      <!-- tag::_liquid -->
      {%- assign name = 'World' -%}
      <!-- end::_liquid -->

      Hello {{ name }} outside.

      <!-- tag::universal-block -->
      Inside {{ name }}.
      <!-- end::universal-block -->
    ADOC
  end

  let(:target_content) do
    <<~ADOC
      <!-- tag::_liquid -->
      <!-- end::_liquid -->

      Hello {{ name }} outside.

      <!-- tag::universal-block -->
      <!-- end::universal-block -->
    ADOC
  end

  let(:prime_path) { File.join(Dir.tmpdir, 'preamble_prime.adoc') }
  let(:target_path) { File.join(Dir.tmpdir, 'preamble_target.adoc') }

  before do
    File.write(prime_path, prime_content)
    File.write(target_path, target_content)
  end

  after do
    FileUtils.rm_f(prime_path)
    FileUtils.rm_f(target_path)
  end

  it 'persists liquid variables from _liquid block to subsequent content' do
    # Verify prime segments for debug
    require 'sourcerer/sync/block_parser'
    Sourcerer::Sync::BlockParser.parse(File.read(prime_path))
    # puts "SEGMENTS: #{segments.map { |s| s.is_a?(Sourcerer::Sync::BlockParser::Block) ? s.tag : 'text' }}"

    result = Sourcerer::Sync.sync(prime_path, target_path, data: { 'dummy' => true })

    updated_content = File.read(target_path)
    # puts "UPDATED CONTENT:\n#{updated_content}"

    expect(updated_content).to include('Inside World.')
    expect(updated_content).to include('Hello World outside.')
    expect(result.applied_changes).to include('_liquid', 'universal-block', 'document-text')
  end
end
