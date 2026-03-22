# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../../../lib/sourcerer/util/pathifier'

RSpec.describe Sourcerer::Util::Pathifier do
  # Use known paths in the repo as stable fixtures.
  let(:fixture_dir)  { File.expand_path('../../../fixtures', __dir__) }
  let(:fixture_file) { File.join(fixture_dir, 'kitchen-sink.adoc') }

  describe '.match' do
    it 'returns a Result struct' do
      result = described_class.match(fixture_file)
      expect(result).to be_a(Sourcerer::Util::Pathifier::Result)
    end

    it 'Result has :type, :input, and :enum fields' do
      result = described_class.match(fixture_file)
      expect(result).to respond_to(:type, :input, :enum)
    end
  end

  # -- :file -------------------------------------------------------------------
  describe 'file input' do
    subject(:result) { described_class.match(fixture_file) }

    it 'classifies as :file' do
      expect(result.type).to eq(:file)
    end

    it 'enum yields exactly one path' do
      paths = result.enum.to_a
      expect(paths.size).to eq(1)
    end

    it 'yields the absolute path' do
      expect(result.enum.first).to eq(File.expand_path(fixture_file))
    end
  end

  # -- :dir --------------------------------------------------------------------
  describe 'directory input' do
    subject(:result) { described_class.match(fixture_dir) }

    it 'classifies as :dir' do
      expect(result.type).to eq(:dir)
    end

    it 'enum is an Enumerator' do
      expect(result.enum).to be_a(Enumerator)
    end

    it 'enum yields at least one path' do
      expect(result.enum.first).not_to be_nil
    end

    context 'with recursive: false' do
      subject(:result) { described_class.match(fixture_dir, recursive: false) }

      it 'yields only direct children' do
        paths = result.enum.to_a
        paths.each do |p|
          expect(File.dirname(p)).to eq(File.expand_path(fixture_dir))
        end
      end
    end

    context 'with include_dirs: true' do
      subject(:result) { described_class.match(fixture_dir, recursive: false, include_dirs: true) }

      it 'includes at least one directory entry' do
        paths  = result.enum.to_a
        dirs   = paths.select { |p| File.directory?(p) }
        expect(dirs).not_to be_empty
      end
    end

    context 'with include_dirs: false (default)' do
      it 'yields only files' do
        paths = described_class.match(fixture_dir).enum.to_a
        paths.each { |p| expect(File.file?(p)).to be true }
      end
    end
  end

  # -- :glob -------------------------------------------------------------------
  describe 'glob input' do
    subject(:result) { described_class.match(glob) }

    let(:glob) { File.join(fixture_dir, '**', '*.adoc') }

    it 'classifies as :glob' do
      expect(result.type).to eq(:glob)
    end

    it 'enum yields matching files' do
      expect(result.enum.to_a).not_to be_empty
    end

    context 'when glob matches nothing' do
      subject(:result) { described_class.match(File.join(fixture_dir, '**', '*.xyz_nonexistent')) }

      it 'still classifies as :glob (has metacharacters)' do
        expect(result.type).to eq(:glob)
      end

      it 'enum yields nothing' do
        expect(result.enum.to_a).to be_empty
      end
    end
  end

  # -- :missing ----------------------------------------------------------------
  describe 'missing input' do
    subject(:result) { described_class.match('/no/such/path/ever/exists.adoc') }

    it 'classifies as :missing' do
      expect(result.type).to eq(:missing)
    end

    it 'enum yields nothing' do
      expect(result.enum.to_a).to be_empty
    end
  end
end
