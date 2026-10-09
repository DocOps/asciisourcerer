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
      # Substitution only ever applies to a *top-level output* `{{ }}`
      # tag -- never to a `Liquid::Variable` some other tag builds
      # privately to parse its own syntax. `Assign`, for example, does
      # exactly that (`lib/liquid/tags/assign.rb`: `@from = Variable.new(
      # $2, options)`, then `@from.render(context)` directly), and that
      # Variable's `#render` is the same patched method, with the same
      # global toggle active. Without this distinction,
      # `{% assign name = data.missing %}` under `preserve_missing: true`
      # would assign the *reconstructed source text of the assign's own
      # right-hand side* (a String) to `name`, rather than the real `nil`
      # -- corrupting every later `{{ name }}` reference instead of
      # leaving it to render its own clean placeholder. `BlockBodyPatch`
      # below marks the one call site (`BlockBody#render_node_to_output`,
      # when the node being rendered is itself a `Variable`) that
      # corresponds to a literal `{{ }}` sitting directly in a template
      # body's nodelist -- the only place a Variable's rendered text
      # actually becomes document output. Any other tag's internal use of
      # a Variable to compute a value (Assign's right-hand side, or
      # anything similar) renders outside that marker and is left with
      # Liquid's normal nil/empty behavior, exactly as if this feature
      # were off.
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

        def self.top_level_output?
          Thread.current[:sourcerer_rendering_output_variable] == true
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
        # `render` untouched unless: this Variable is currently being
        # rendered as a top-level output node (see `BlockBodyPatch`
        # below), preserve-missing/-empty is active for this thread, and
        # the fully-filtered result counts as missing (nil) or empty (a
        # defined-but-empty String/Array/Hash).
        module VariablePatch
          def render context
            result = super
            return result unless PreserveMissingVariables.top_level_output?
            return "{{#{raw}}}" if PreserveMissingVariables.preserve_missing? && result.nil?
            return "{{#{raw}}}" if PreserveMissingVariables.preserve_empty? && empty_result?(result)

            result
          end

          private

          def empty_result? value
            value.respond_to?(:empty?) && value.empty?
          end
        end

        # Prepended onto ::Liquid::BlockBody. `render_node_to_output` is
        # the one call site where a node from a body's own nodelist --
        # i.e. a literal `{{ }}` or `{% tag %}` written directly in
        # template source -- gets rendered and appended to output. We
        # only care about the `Variable` case: that's a genuine top-level
        # `{{ }}` output tag, as opposed to a `Variable` some other tag
        # (Assign, etc.) builds privately and renders itself, bypassing
        # BlockBody entirely. See {PreserveMissingVariables} above for why
        # this distinction matters.
        module BlockBodyPatch
          # rubocop:disable-next Style/OptionalBooleanParameter -- must match
          # ::Liquid::BlockBody#render_node_to_output's own positional signature
          def render_node_to_output node, output, context, skip_output = false
            return super unless node.is_a?(::Liquid::Variable)

            previous = Thread.current[:sourcerer_rendering_output_variable]
            Thread.current[:sourcerer_rendering_output_variable] = true
            super
          ensure
            Thread.current[:sourcerer_rendering_output_variable] = previous if node.is_a?(::Liquid::Variable)
          end
        end
      end
    end
  end
end

Liquid::Variable.prepend(Sourcerer::Jekyll::Liquid::PreserveMissingVariables::VariablePatch)
Liquid::BlockBody.prepend(Sourcerer::Jekyll::Liquid::PreserveMissingVariables::BlockBodyPatch)
