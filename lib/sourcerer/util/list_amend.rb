# frozen_string_literal: true

module Sourcerer
  module Util
    # Merge a user-supplied list into a default list using +/- amendment tokens.
    #
    # Not required internally; callers must require this file explicitly.
    module ListAmend
      # Apply a custom list on top of a default list.
      #
      # @param default_list [Array<#to_s>] the baseline list of items
      # @param custom_list  [nil, String, Array<#to_s>] the user-supplied overrides
      # @param normalize    [nil, #call] optional normalizer for deduplication comparisons (e.g. +:downcase+.to_proc)
      # @return [Array<String>]
      #
      # Behavior:
      #   - +nil+ / empty custom ⇒ return stringified +default_list+
      #   - custom with no +/- tokens ⇒ fixed-list mode: return stringified custom
      #   - custom with any +/- token ⇒ amendment mode:
      #       -slug  removes slug from working set (or no-op)
      #       +slug  adds slug if not already present
      #       bare   treated as +slug
      def self.apply default_list, custom_list, normalize: nil
        tokens = parse_tokens(custom_list)
        return default_list.map(&:to_s) if tokens.empty?

        amendment_mode = tokens.any? { |t| t.start_with?('+', '-') }
        return tokens.map(&:to_s) unless amendment_mode

        working = default_list.map(&:to_s)
        norm    = normalize || ->(s) { s }

        # Apply removals first, then additions in token order.
        tokens.each do |token|
          if token.start_with?('-')
            slug = token[1..]
            working.reject! { |item| norm.call(item) == norm.call(slug) }
          else
            slug = token.start_with?('+') ? token[1..] : token
            working << slug unless working.any? { |item| norm.call(item) == norm.call(slug) }
          end
        end

        working
      end

      # Normalize a raw custom_list value into an array of non-empty token strings.
      def self.parse_tokens raw
        case raw
        when nil
          []
        when Array
          raw.map(&:to_s).reject(&:empty?)
        when String
          raw.split(/[\s,]+/).reject(&:empty?)
        else
          Array(raw).map(&:to_s).reject(&:empty?)
        end
      end
      private_class_method :parse_tokens
    end
  end
end
