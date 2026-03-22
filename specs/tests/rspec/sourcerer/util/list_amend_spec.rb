# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../../../lib/sourcerer/util/list_amend'

RSpec.describe Sourcerer::Util::ListAmend do
  let(:defaults) { %w[a b c] }

  describe '.apply' do
    # -- nil / empty custom ---------------------------------------------------
    context 'when custom_list is nil' do
      it 'returns stringified default_list' do
        expect(described_class.apply(defaults, nil)).to eq(%w[a b c])
      end
    end

    context 'when custom_list is an empty string' do
      it 'returns stringified default_list' do
        expect(described_class.apply(defaults, '')).to eq(%w[a b c])
      end
    end

    context 'when custom_list is an empty array' do
      it 'returns stringified default_list' do
        expect(described_class.apply(defaults, [])).to eq(%w[a b c])
      end
    end

    # -- fixed-list mode (no +/- tokens) --------------------------------------
    context 'when custom_list has no + or - tokens' do
      it 'returns the custom list as strings, replacing defaults' do
        expect(described_class.apply(defaults, 'b c')).to eq(%w[b c])
      end

      it 'accepts an Array as custom_list' do
        expect(described_class.apply(defaults, %w[x y])).to eq(%w[x y])
      end

      it 'accepts comma-separated string' do
        expect(described_class.apply(defaults, 'b,c')).to eq(%w[b c])
      end
    end

    # -- amendment mode -------------------------------------------------------
    context 'when custom_list contains any + or - token' do
      it 'removes items with - prefix' do
        expect(described_class.apply(defaults, '-b')).to eq(%w[a c])
      end

      it 'adds items with + prefix' do
        expect(described_class.apply(defaults, '+d')).to eq(%w[a b c d])
      end

      it 'treats bare tokens as additions in amendment mode' do
        expect(described_class.apply(defaults, '-b d')).to eq(%w[a c d])
      end

      it 'applies mixed + and - tokens' do
        expect(described_class.apply(defaults, '-b +d')).to eq(%w[a c d])
      end

      it 'is a no-op when removing a non-existent item' do
        expect(described_class.apply(defaults, '-z')).to eq(%w[a b c])
      end

      it 'does not duplicate when adding an existing item via +' do
        expect(described_class.apply(defaults, '+a')).to eq(%w[a b c])
      end

      it 'does not duplicate when adding an existing item as bare token' do
        expect(described_class.apply(defaults, '-c a')).to eq(%w[a b])
      end

      it 'preserves default order with removals, then appends additions' do
        result = described_class.apply(defaults, '-a +z +b')
        # a removed, z added, b already present so no dup
        expect(result).to eq(%w[b c z])
      end

      it 'accepts comma-separated amendment tokens' do
        expect(described_class.apply(defaults, '-b,+d')).to eq(%w[a c d])
      end
    end

    # -- normalize option -----------------------------------------------------
    context 'with a normalize callable' do
      let(:ci) { lambda(&:downcase) }

      it 'uses the normalizer for deduplication in amendment mode' do
        result = described_class.apply(%w[A B C], '+a', normalize: ci)
        # 'a' matches 'A' normalised ⇒ no addition
        expect(result).to eq(%w[A B C])
      end

      it 'uses the normalizer for removal matching' do
        result = described_class.apply(%w[A B C], '-A', normalize: ci)
        expect(result).to eq(%w[B C])
      end
    end
  end
end
