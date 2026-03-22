# frozen_string_literal: true

require_relative 'sync/block_parser'
require_relative 'sync/cast'

module Sourcerer
  # Canonical block synchronization and Liquid rendering for flat text files.
  #
  # @see Sourcerer::Sync::Cast  The main orchestrator class.
  # @see Sourcerer::Sync::BlockParser  The file-agnostic block parser.
  # @see https://github.com/DocOps/asciisourcerer Sync/Cast documentation
  module Sync
    # Synchronise canonical blocks from `prime_path` into `target_path`.
    #
    # @param prime_path [String]
    # @param target_path [String]
    # @param options [Hash] Passed through to {Cast.sync}.
    # @return [Cast::CastResult]
    def self.sync(prime_path, target_path, **)
      Cast.sync(prime_path, target_path, **)
    end

    # Bootstrap a brand-new target file from the prime template.
    #
    # @param prime_path [String]
    # @param target_path [String]
    # @param options [Hash] Passed through to {Cast.init}.
    # @return [Cast::CastResult]
    def self.init(prime_path, target_path, **)
      Cast.init(prime_path, target_path, **)
    end
  end
end
