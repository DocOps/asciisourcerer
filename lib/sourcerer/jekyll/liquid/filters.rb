# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'kramdown-asciidoc'

module Sourcerer
  module Jekyll
    module Liquid
      # Liquid-facing filters for Sourcerer's Jekyll-compatible runtime.
      #
      # Public methods in this module are the filter wrappers consumed by Liquid.
      # Core transformation logic lives in `Ops` so behavior is reusable and easier
      # to test/refactor without changing the Liquid surface.
      module Filters
        # Internal operations for filter behavior.
        module Ops
          module_function

          def render input, vars=nil
            scope = vars.is_a?(Hash) ? vars.transform_keys(&:to_s) : {}

            template =
              if input.respond_to?(:render) && input.respond_to?(:templated?) && input.templated?
                input
              else
                ::Liquid::Template.parse(input.to_s)
              end

            template.render(scope)
          end

          def sluggerize input, format='kebab'
            return input unless input.is_a?(String)

            case format
            when 'kebab' then input.downcase.gsub(/[\s\-_]/, '-')
            when 'snake' then input.downcase.gsub(/[\s\-_]/, '_')
            when 'camel' then input.downcase.gsub(/[\s\-_]/, '_').camelize(:lower)
            when 'pascal' then input.downcase.gsub(/[\s\-_]/, '_').camelize(:upper)
            else input
            end
          end

          def plusify input
            input.gsub(/\n\n+/, "\n+\n")
          end

          def md_to_adoc input, wrap='ventilate'
            options = {}
            options[:wrap] = wrap.to_sym if wrap
            Kramdoc.convert(input, options)
          end

          def indent input, spaces=2, line1: false
            indent = ' ' * spaces
            lines = input.split("\n")
            indented = if line1
                         lines.map { |line| indent + line }
                       else
                         lines.map.with_index { |line, i| i.zero? ? line : indent + line }
                       end
            indented.join("\n")
          end

          def ruby_class input
            input.class.name
          end

          def title_caps input, hyphen=false
            return input unless input.is_a?(String)

            if hyphen
              input.gsub(/(^|[\s-])([[:alpha:]])/) { "#{::Regexp.last_match(1)}#{::Regexp.last_match(2).upcase}" }
            else
              input.gsub(/(^|\s)([[:alpha:]])/) { "#{::Regexp.last_match(1)}#{::Regexp.last_match(2).upcase}" }
            end
          end

          def demarkupify input
            return input unless input.is_a?(String)

            input = input.gsub(/`"|"`/, '"')
            input = input.gsub(/'`|`'/, "'")
            input = input.gsub(/[*_`]/, '')
            input = input.gsub(/[“”]/, '"')
            input.gsub(/[‘’]/, "'")
          end

          def inspect_yaml input
            require 'yaml'
            YAML.dump(input)
          end

          def base64 input
            return input unless input.is_a?(String)

            Base64.strict_encode64(input)
          end

          def base64_decode input
            return input unless input.is_a?(String)

            Base64.strict_decode64(input)
          rescue ArgumentError
            input
          end

          def html_escape input
            CGI.escapeHTML(input.to_s)
          end

          def html_unescape input
            CGI.unescapeHTML(input.to_s)
          end
        end
        private_constant :Ops

        def render input, vars=nil
          Ops.render(input, vars)
        end

        def sluggerize input, format='kebab'
          Ops.sluggerize(input, format)
        end

        def plusify input
          Ops.plusify(input)
        end

        def md_to_adoc input, wrap='ventilate'
          Ops.md_to_adoc(input, wrap)
        end

        def indent input, spaces=2, line1: false
          Ops.indent(input, spaces, line1: line1)
        end

        def ruby_class input
          Ops.ruby_class(input)
        end

        def title_caps input, hyphen=false
          Ops.title_caps(input, hyphen)
        end

        def demarkupify input
          Ops.demarkupify(input)
        end

        def inspect_yaml input
          Ops.inspect_yaml(input)
        end

        def base64 input
          Ops.base64(input)
        end

        def base64_decode input
          Ops.base64_decode(input)
        end

        def html_escape input
          Ops.html_escape(input)
        end

        def html_unescape input
          Ops.html_unescape(input)
        end
      end
    end
  end
end
