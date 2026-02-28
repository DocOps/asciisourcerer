# frozen_string_literal: true

require 'yaml'
require 'psych'
require 'date'

module Sourcerer
  # Lightweight YAML parsing helpers with optional AsciiDoc attribute resolution.
  module Yaml
    # Parse a YAML string and resolve AsciiDoc attribute references like `{attribute_name}`.
    #
    # @param yaml [String] The YAML string to parse.
    # @param attrs [Hash] The AsciiDoc attributes to use for resolution.
    # @return [Hash] The loaded YAML data with attributes resolved.
    def self.parse_with_attributes yaml, attrs = {}
      raw_data = parse_with_tags(yaml)
      AttributeResolver.resolve_attributes!(raw_data, attrs)
      raw_data
    end

    # Parse a YAML string, preserving any custom tags (e.g., `!foo`).
    # Custom tags are attached to the data structure.
    #
    # @param yaml [String] The YAML string to parse.
    # @return [Hash] The loaded YAML data with custom tags attached.
    def self.parse_with_tags yaml
      return {} if yaml.nil? || yaml.strip.empty?

      data = Psych.load(yaml, aliases: true, permitted_classes: [Date, Time])
      ast  = Psych.parse(yaml)
      attach_tags(ast.root, data)
      data
    end

    # Load a YAML file and resolve AsciiDoc attribute references like `{attribute_name}`.
    #
    # @param path [String] The path to the YAML file.
    # @param attrs [Hash] The AsciiDoc attributes to use for resolution.
    # @return [Hash] The loaded YAML data with attributes resolved.
    def self.load_with_attributes path, attrs = {}
      parse_with_attributes(File.read(path), attrs)
    end

    # Load a YAML file, preserving any custom tags (e.g., `!foo`).
    # Custom tags are attached to the data structure.
    #
    # @param path [String] The path to the YAML file.
    # @return [Hash] The loaded YAML data with custom tags attached.
    def self.load_with_tags path
      return {} if File.empty?(path)

      parse_with_tags(File.read(path))
    end

    # Recursively attach YAML tags to the loaded data structure.
    #
    # @param node [Psych::Nodes::Node] The current AST node.
    # @param data [Object] The data corresponding to the current node.
    # @api private
    def self.attach_tags node, data
      return unless node.is_a?(Psych::Nodes::Mapping)

      node.children.each_slice(2) do |key_node, val_node|
        key = key_node.value

        if val_node.respond_to?(:tag) && val_node.tag && data[key].is_a?(String)
          normalized_tag = val_node.tag.sub(/^!+/, '').sub(/^.*:/, '')
          data[key] = {
            'value' => data[key],
            '__tag__' => normalized_tag
          }
        elsif data[key].is_a?(Hash)
          attach_tags(val_node, data[key])
        end
      end
    end

    # Resolves AsciiDoc attribute references like `{attribute_name}` in YAML values.
    module AttributeResolver
      # Recursively walk a schema Hash and resolve `{attribute_name}` references
      # in `dflt` values.
      #
      # @param schema [Hash] The schema or definition hash to process.
      # @param attrs [Hash] The key-value pairs from AsciiDoc attributes to use for resolution.
      # @return [Hash] The schema with resolved attributes.
      def self.resolve_attributes! schema, attrs
        case schema
        when Hash
          schema.transform_values! do |value|
            if value.is_a?(Hash)
              if value.key?('dflt') && value['dflt'].is_a?(String)
                value['dflt'] = resolve_attribute_reference(value['dflt'], attrs)
              end
              resolve_attributes!(value, attrs)
            else
              value
            end
          end
        end
        schema
      end

      # Replace `{attribute_name}` patterns with corresponding values from attrs.
      #
      # @param value [String] The string to process.
      # @param attrs [Hash] The attributes to use for resolution.
      # @return [String] The processed string with attribute references replaced.
      def self.resolve_attribute_reference value, attrs
        return value unless value.match?(/\{[^}]+\}/)

        value.gsub(/\{([^}]+)\}/) do |match|
          attr_name = ::Regexp.last_match(1)
          attrs[attr_name] || match
        end
      end
    end

    # Utility methods for working with YAML-sourced data adorned with tags
    module TagUtils
      # Extracts the original value from a tagged data structure.
      #
      # @param value [Object] The tagged value (a Hash) or any other value.
      # @return [Object] The original value, or the value itself if not tagged.
      def self.detag value
        value.is_a?(Hash) && value.key?('value') ? value['value'] : value
      end

      # Retrieves the tag from a tagged data structure.
      #
      # @param value [Object] The tagged value (a Hash) or any other value.
      # @return [String, nil] The tag string, or `nil` if not tagged.
      def self.tag_of value
        value.is_a?(Hash) ? value['__tag__'] : nil
      end

      # Checks if a value has a specific tag.
      #
      # @param value [Object] The tagged value to check.
      # @param tag [String, Symbol] The tag to check for.
      # @return [Boolean] `true` if the value has the specified tag, `false` otherwise.
      def self.tag? value, tag
        tag_of(value)&.to_s == tag.to_s
      end
    end
  end
end
