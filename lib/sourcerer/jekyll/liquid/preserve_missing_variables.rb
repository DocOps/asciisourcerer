# frozen_string_literal: true

require 'liquid'

module Sourcerer
  module Jekyll
    module Liquid
      # Opt-in alternative to Liquid's default "render nil/empty as empty
      # string" behavior: when active, a `{{ ... }}` expression that
      # evaluates to a missing or empty value renders as its own original
      # source text (e.g. `{{ data.foo | capitalize }}`) instead of
      # vanishing. Useful for document templates where an unfilled field
      # should stay visible for the preparer to fill in by hand, rather
      # than silently disappearing.
      #
      # Two independent toggles, each off by default:
      #
      # - `preserve_missing`: an outright `nil` result is preserved.
      # - `preserve_empty`: a defined-but-empty String/Array/Hash result
      #   (`""`, `[]`, `{}`) is preserved.
      #
      # Neither affects the other's target, and neither affects `0` or
      # `false`. Both checks run against the fully-filtered result (i.e.
      # any `| filters` in the tag have already run), matching what Liquid
      # itself would otherwise render -- we never re-run the filters, we
      # just restore the tag's own pre-render source text once a render
      # has been judged missing/empty. `raw` is used verbatim (no
      # whitespace trimming), so the reconstructed tag matches the
      # original byte-for-byte -- except for `{{-`/`-}}` whitespace
      # control markers, which Liquid's tokenizer strips before the
      # markup ever reaches a `Variable` instance and so cannot be
      # recovered here.
      #
      # Liquid 4 has no built-in hook for this -- there is no Environment or
      # parser-injection point (introduced only in Liquid 5) to substitute a
      # custom Variable class per template -- so this prepends onto
      # `::Liquid::Variable` globally and gates the actual behavior change
      # with toggles scoped to one render call. See
      # `Sourcerer::Rendering.render_template`'s `preserve_missing:`/
      # `preserve_empty:` options, which flip these toggles for the
      # duration of that one render.
      module PreserveMissingVariables
        def self.preserve_missing?
          Thread.current[:sourcerer_preserve_missing] == true
        end

        def self.preserve_empty?
          Thread.current[:sourcerer_preserve_empty] == true
        end

        # Activates preserve-missing/-empty rendering for the duration of
        # the block. Restores the prior values afterward so nested/
        # sequential renders that don't ask for it are unaffected.
        #
        # @param preserve_missing [Boolean] See {PreserveMissingVariables}.
        # @param preserve_empty [Boolean] See {PreserveMissingVariables}.
        def self.with_active preserve_missing: false, preserve_empty: false
          previous_missing = Thread.current[:sourcerer_preserve_missing]
          previous_empty = Thread.current[:sourcerer_preserve_empty]
          Thread.current[:sourcerer_preserve_missing] = preserve_missing
          Thread.current[:sourcerer_preserve_empty] = preserve_empty
          yield
        ensure
          Thread.current[:sourcerer_preserve_missing] = previous_missing
          Thread.current[:sourcerer_preserve_empty] = previous_empty
        end

        # Prepended onto ::Liquid::Variable. Falls through to Liquid's own
        # `render` untouched unless the fully-filtered result counts as
        # missing (nil, when `preserve_missing` is active) or empty (a
        # defined-but-empty String/Array/Hash, when `preserve_empty` is
        # active).
        module VariablePatch
          def render context
            result = super
            return "{{#{raw}}}" if PreserveMissingVariables.preserve_missing? && result.nil?
            return "{{#{raw}}}" if PreserveMissingVariables.preserve_empty? && empty_result?(result)

            result
          end

          private

          def empty_result? value
            value.respond_to?(:empty?) && value.empty?
          end
        end
      end
    end
  end
end

Liquid::Variable.prepend(Sourcerer::Jekyll::Liquid::PreserveMissingVariables::VariablePatch)
