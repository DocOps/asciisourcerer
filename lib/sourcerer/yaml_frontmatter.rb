# frozen_string_literal: true

require 'yaml'

module Sourcerer
  # Single owner of YAML frontmatter parsing across Sourcerer.
  #
  # Both AsciiDoc pages (the Jekyll convention of embedding +---+-fenced YAML
  # at the top of a +.adoc+ file) and Markdown pages use the same syntax.
  # All Sourcerer code that needs to detect, extract, or remove a frontmatter
  # block delegates here instead of duplicating logic or constants.
  module YamlFrontmatter
    # Matches a leading +---+-fenced YAML block at the start of a file.
    # Content between the fences must be non-empty (+.+?+, lazy).
    # The closing fence must be followed by a newline.
    REGEXP = /\A(---\s*\n.+?\n)(---\s*\n)/m

    module_function

    # Parse the YAML frontmatter from +source_text+ and return it as a Hash.
    #
    # Returns an empty Hash when no frontmatter is present or when the YAML
    # is malformed.
    #
    # @param source_text [String]
    # @return [Hash]
    def extract source_text
      match = source_text.match(REGEXP)
      return {} unless match

      frontmatter_payload = match[1].sub(/\A---\s*\n/, '')
      parsed = YAML.safe_load(frontmatter_payload, aliases: true)
      parsed.is_a?(Hash) ? parsed : {}
    rescue Psych::SyntaxError
      {}
    end

    # Return +source_text+ with the leading YAML frontmatter block removed.
    #
    # @param source_text [String]
    # @return [String]
    def strip source_text
      source_text.sub(REGEXP, '')
    end
  end
end
