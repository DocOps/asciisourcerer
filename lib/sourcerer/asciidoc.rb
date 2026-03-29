# frozen_string_literal: true

require 'asciidoctor'
require 'fileutils'
require 'yaml'
require 'cgi'
require_relative 'yaml_frontmatter'

module Sourcerer
  # AsciiDoc-focused primitives for attribute loading, region extraction,
  # includes, and converter-oriented utilities.
  # AsciiDoc processing module for document conversion and content extraction.
  #
  # This module provides utilities for working with AsciiDoc files, including:
  # - Loading document attributes and snippets via include directives
  # - Extracting tagged content from files
  # - Converting AsciiDoc to HTML, manpage, and Markdown formats
  # - Managing YAML front matter in AsciiDoc documents
  # - Extracting commands from code blocks with specific roles
  #
  # @example Loading attributes from an AsciiDoc file
  #   attributes = AsciiDoc.load_attributes('path/to/file.adoc')
  #
  # @example Converting AsciiDoc to Markdown
  #   result = AsciiDoc.mark_down_grade(
  #     'source.adoc',
  #     markdown_output_path: 'output.md',
  #     include_frontmatter: true
  #   )
  #
  # @example Extracting tagged content
  #   content = AsciiDoc.extract_tagged_content(
  #     'file.adoc',
  #     tags: ['snippet1', 'snippet2']
  #   )
  #
  # @see https://asciidoctor.org/ Asciidoctor Documentation
  module AsciiDoc
    YAML_FRONTMATTER_REGEXP = Sourcerer::YamlFrontmatter::REGEXP
    YAML_FRONT_MATTER_REGEXP = YAML_FRONTMATTER_REGEXP
    PAGE_ATTRIBUTE_PREFIX = 'page-'

    # Loads AsciiDoc attributes from a document header as a Hash.
    #
    # @param path [String] The path to the AsciiDoc file.
    # @return [Hash] A hash of the document attributes.
    def self.load_attributes path
      doc = Asciidoctor.load_file(path, safe: :unsafe)
      doc.attributes
    end

    # Loads a snippet from an AsciiDoc file using an `include::` directive.
    #
    # @param path_to_main_adoc [String] The path to the main AsciiDoc file.
    # @param tag [String] A single tag to include.
    # @param tags [Array<String>] An array of tags to include.
    # @param leveloffset [Integer] The level offset for the include.
    # @return [String] The content of the included snippet.
    def self.load_include path_to_main_adoc, tag: nil, tags: [], leveloffset: nil
      opts = []
      opts << "tag=#{tag}" if tag
      opts << "tags=#{tags.join(',')}" if tags.any?
      opts << "leveloffset=#{leveloffset}" if leveloffset

      snippet_doc = <<~ADOC
        include::#{path_to_main_adoc}[#{opts.join(', ')}]
      ADOC

      doc = Asciidoctor.load(
        snippet_doc,
        safe: :unsafe,
        base_dir: File.expand_path('.'),
        header_footer: false,
        attributes: { 'source-highlighter' => nil })

      doc.blocks.map(&:content).join("\n")
    end

    # Extracts tagged content from a file.
    #
    # @param path_to_tagged_adoc [String] The path to the file with tagged content.
    # @param tag [String] A single tag to extract.
    # @param tags [Array<String>] An array of tags to extract.
    # @param comment_prefix [String] The prefix for comment lines.
    # @param comment_suffix [String] The suffix for comment lines.
    # @param skip_comments [Boolean] Whether to skip comment lines in the output.
    # @return [String] The extracted content.
    def self.extract_tagged_content path_to_tagged_adoc, **options
      options = normalize_extract_tagged_content_options(options)
      tags = normalize_extract_tags(options[:tag], options[:tags])
      collect_tagged_content(
        path_to_tagged_adoc,
        tags: tags,
        comment_prefix: options[:comment_prefix],
        skip_comments: options[:skip_comments])
    end

    # @api private
    def self.normalize_extract_tagged_content_options options
      supported_option_keys = %i[tag tags comment_prefix comment_suffix skip_comments]
      unknown_option_keys = options.keys - supported_option_keys
      raise ArgumentError, "unknown option(s): #{unknown_option_keys.join(', ')}" unless unknown_option_keys.empty?

      {
        tag: options[:tag],
        tags: options.fetch(:tags, []),
        comment_prefix: options.fetch(:comment_prefix, '// '),
        skip_comments: options.fetch(:skip_comments, false)
      }
    end

    # @api private
    def self.normalize_extract_tags tag, tags
      raise ArgumentError, 'tag and tags cannot coexist' if tag && !tags.empty?

      tags = [tag] if tag
      raise ArgumentError, 'at least one tag must be specified' if tags.empty?
      raise ArgumentError, 'tags must all be strings' unless tags.all? { |item| item.is_a?(String) }

      tags
    end

    # @api private
    def self.collect_tagged_content path_to_tagged_adoc, tags:, comment_prefix:, skip_comments:
      tagged_content = []
      open_tags = {}
      tag_comment_prefix = comment_prefix.strip || '//'
      tag_pattern = /^#{Regexp.escape(tag_comment_prefix)}\s*tag::([\w-]+)\[\]/
      end_pattern = /^#{Regexp.escape(tag_comment_prefix)}\s*end::([\w-]+)\[\]/
      comment_line_init_pattern = /^#{Regexp.escape(tag_comment_prefix)}+/
      collecting = false

      File.open(path_to_tagged_adoc, 'r') do |file|
        file.each_line do |line|
          if line =~ tag_pattern
            tag_name = Regexp.last_match(1)
            if tags.include?(tag_name)
              collecting = true
              open_tags[tag_name] = true
            end
          elsif line =~ end_pattern
            tag_name = Regexp.last_match(1)
            if open_tags[tag_name]
              open_tags.delete(tag_name)
              collecting = false if open_tags.empty?
            end
          elsif collecting
            tagged_content << line unless skip_comments && line =~ comment_line_init_pattern
          end
        end
      end

      tagged_content.empty? ? '' : tagged_content.join
    end

    # Generates a manpage from an AsciiDoc source file.
    #
    # @param source_adoc [String] The path to the source AsciiDoc file.
    # @param target_manpage [String] The path to the target manpage file.
    def self.generate_manpage source_adoc, target_manpage
      FileUtils.mkdir_p(File.dirname(target_manpage))
      Asciidoctor.convert_file(
        source_adoc,
        backend: 'manpage',
        safe: :unsafe,
        standalone: true,
        to_file: target_manpage)
    end

    # Generates HTML from an AsciiDoc source file.
    #
    # @param source_adoc [String] The path to the source AsciiDoc file.
    # @param target_html [String] The path to the target HTML file.
    # @param backend [String] Backend selector (`asciidoctor-html5s` or `html5`).
    # @param header_footer [Boolean] Whether to emit full HTML document wrapper.
    # @return [String] The backend used for generation.
    def self.generate_html source_adoc, target_html, backend: 'asciidoctor-html5s', header_footer: false
      FileUtils.mkdir_p(File.dirname(target_html))

      selected_backend = resolve_html_backend(backend)
      Asciidoctor.convert_file(
        source_adoc,
        backend: selected_backend,
        safe: :unsafe,
        header_footer: header_footer,
        to_file: target_html)

      selected_backend
    end

    # Convert AsciiDoc source to Markdown through an interim HTML conversion.
    #
    # @param source_path [String] Path to AsciiDoc source file.
    # @param markdown_output_path [String, nil] Optional markdown output path.
    # @param html_output_path [String, nil] Optional HTML output path.
    # @param backend [String] HTML backend request (`html5` or `asciidoctor-html5s`).
    # @param header_footer [Boolean] Whether interim HTML should include document wrapper.
    # @param include_frontmatter [Boolean] Whether to prepend markdown YAML front matter.
    # @param markdown_options [Hash] Options passed to markdown converter.
    # @param markdown_converter [#call] Callable that accepts `(html, markdown_options)`.
    # @return [Hash] Conversion result containing markdown, frontmatter, and backend info.
    def self.mark_down_grade source_path, markdown_output_path=nil, markdown_converter:, **options
      options = normalize_mark_down_grade_options(options)

      source_text = File.read(source_path)
      conversion_source_text = strip_yaml_frontmatter(source_text)
      selected_backend = resolve_html_backend(options[:backend])
      document = load_document_for_markdown_grade(
        source_path,
        conversion_source_text,
        backend: selected_backend,
        header_footer: options[:header_footer],
        attributes: options[:attributes])

      frontmatter = options[:include_frontmatter] ? extract_frontmatter(source_text, document.attributes) : {}
      html_body = document.convert
      html_body = ensure_document_title(html_body, document.doctitle)
      html_with_frontmatter = options[:include_frontmatter] ? prepend_frontmatter(html_body, frontmatter) : html_body

      if options[:html_output_path]
        FileUtils.mkdir_p(File.dirname(options[:html_output_path]))
        File.write(options[:html_output_path], html_with_frontmatter)
      end

      frontmatter_block, html_for_markdown = split_frontmatter_block(html_with_frontmatter)
      markdown_body = markdown_converter.call(html_for_markdown, options[:markdown_options])
      markdown = frontmatter_block ? "#{frontmatter_block}\n\n#{markdown_body}" : markdown_body

      if markdown_output_path
        FileUtils.mkdir_p(File.dirname(markdown_output_path))
        File.write(markdown_output_path, markdown)
      end

      {
        markdown: markdown,
        frontmatter: frontmatter,
        requested_backend: options[:backend],
        used_backend: selected_backend
      }
    end

    # @api private
    def self.normalize_mark_down_grade_options options
      supported_option_keys = %i[html_output_path backend header_footer include_frontmatter markdown_options attributes]
      unknown_option_keys = options.keys - supported_option_keys
      raise ArgumentError, "unknown option(s): #{unknown_option_keys.join(', ')}" unless unknown_option_keys.empty?

      {
        html_output_path: options[:html_output_path],
        backend: options.fetch(:backend, 'asciidoctor-html5s'),
        header_footer: options.fetch(:header_footer, false),
        include_frontmatter: options.fetch(:include_frontmatter, true),
        markdown_options: options.fetch(:markdown_options, { github_flavored: true }),
        attributes: options.fetch(:attributes, {})
      }
    end

    # Extract front matter from AsciiDoc text using YAML fences and page-* attributes.
    #
    # @param source_text [String]
    # @param document_attributes [Hash]
    # @return [Hash]
    def self.extract_frontmatter source_text, document_attributes
      page_attrs = extract_page_attributes(document_attributes)
      yaml_frontmatter = extract_yaml_frontmatter(source_text)
      page_attrs.merge(yaml_frontmatter)
    end

    # Build YAML front matter block content from a hash.
    #
    # @param frontmatter [Hash]
    # @return [String, nil]
    def self.compose_frontmatter_block frontmatter
      return nil if frontmatter.nil? || frontmatter.empty?

      yaml_payload = YAML.dump(frontmatter)
      yaml_payload = yaml_payload.sub(/\A---\s*\n/, '')
      yaml_payload = yaml_payload.sub(/\n\.\.\.\s*\z/, "\n")

      "---\n#{yaml_payload}---"
    end

    # Prepend front matter block to content.
    #
    # @param content [String]
    # @param frontmatter [Hash]
    # @return [String]
    def self.prepend_frontmatter content, frontmatter
      block = compose_frontmatter_block(frontmatter)
      return content unless block

      "#{block}\n\n#{content}"
    end

    # Split front matter block from content if present.
    #
    # @param content [String]
    # @return [Array<(String, String)>]
    def self.split_frontmatter_block content
      match = content.match(YAML_FRONTMATTER_REGEXP)
      return [nil, content] unless match

      full_block = "#{match[1]}#{match[2]}".strip
      remainder = content.sub(YAML_FRONTMATTER_REGEXP, '').sub(/\A\n+/, '')
      [full_block, remainder]
    end

    # Parse page-* attributes using Asciidoctor-resolved document attributes.
    #
    # @param document_attributes [Hash]
    # @return [Hash]
    def self.extract_page_attributes document_attributes
      attributes = {}
      prefix = PAGE_ATTRIBUTE_PREFIX

      document_attributes.each do |key, value|
        next unless key.start_with?(prefix)

        normalized_key = key.sub(/\A#{Regexp.escape(prefix)}/, '')
        attributes[normalized_key] = value.to_s
      end

      attributes
    end

    # Parse optional YAML front matter fenced with --- at the top of source content.
    #
    # @param source_text [String]
    # @return [Hash]
    def self.extract_yaml_frontmatter source_text
      Sourcerer::YamlFrontmatter.extract(source_text)
    end

    # Remove leading YAML front matter fence block from AsciiDoc source.
    #
    # @param source_text [String]
    # @return [String]
    def self.strip_yaml_frontmatter source_text
      Sourcerer::YamlFrontmatter.strip(source_text)
    end

    # Compatibility alias.
    def self.compose_front_matter_block frontmatter
      compose_frontmatter_block(frontmatter)
    end

    # Compatibility alias.
    def self.prepend_front_matter content, frontmatter
      prepend_frontmatter(content, frontmatter)
    end

    # Compatibility alias.
    def self.split_front_matter content
      split_frontmatter_block(content)
    end

    # Compatibility alias.
    def self.extract_yaml_front_matter source_text
      extract_yaml_frontmatter(source_text)
    end

    # Compatibility alias.
    def self.strip_yaml_front_matter source_text
      strip_yaml_frontmatter(source_text)
    end

    # @api private
    # Build an Asciidoctor document for markdown-grade pipeline in one parse pass.
    #
    # @param source_path [String]
    # @param source_text [String]
    # @param backend [String]
    # @param header_footer [Boolean]
    # @param attributes [Hash]
    # @return [Asciidoctor::Document]
    def self.load_document_for_markdown_grade source_path, source_text, backend:, header_footer:, attributes: {}
      expanded_source_path = File.expand_path(source_path)
      Asciidoctor.load(
        source_text,
        safe: :unsafe,
        parse: true,
        backend: backend,
        header_footer: header_footer,
        base_dir: File.dirname(source_path),
        attributes: attributes.merge(
          {
            'docfile' => expanded_source_path,
                    'docdir' => File.dirname(expanded_source_path),
                    'docname' => File.basename(source_path, File.extname(source_path))
          }))
    end

    # Extracts commands from listing and literal blocks with a specific role.
    #
    # @param file_path [String] The path to the AsciiDoc file.
    # @param role [String] The role to look for.
    # @return [Array<String>] An array of command groups.
    def self.extract_commands file_path, role: 'testable'
      doc = Asciidoctor.load_file(file_path, safe: :unsafe)
      command_groups = []
      current_group = []

      blocks = doc.find_by(context: :listing) + doc.find_by(context: :literal)

      blocks.each do |block|
        next unless block.has_role?(role)

        commands = process_block_content(block.content)
        if block.has_role?('testable-newshell')
          command_groups << current_group.join("\n") unless current_group.empty?
          command_groups << commands.join("\n") unless commands.empty?
          current_group = []
        else
          current_group.concat(commands)
        end
      end

      command_groups << current_group.join("\n") unless current_group.empty?
      command_groups
    end

    # @api private
    # Processes the content of a block to extract commands.
    # It handles line continuations and skips comments.
    # @param content [String] The content of the block.
    # @return [Array<String>] An array of commands.
    def self.process_block_content content
      processed_commands = []
      current_command = ''

      content.each_line do |line|
        stripped_line = line.strip
        next if stripped_line.start_with?('#')

        if stripped_line.end_with?('\\')
          current_command += "#{stripped_line.chomp('\\')} "
        else
          current_command += stripped_line
          processed_commands << current_command unless current_command.empty?
          current_command = ''
        end
      end

      processed_commands
    end

    # @api private
    # Resolve backend for HTML generation, preferring semantic HTML5 when available.
    #
    # @param backend [String]
    # @return [String]
    def self.resolve_html_backend backend
      return 'html5' if backend.to_s == 'html5'

      begin
        require 'asciidoctor-html5s'
        'html5s'
      rescue LoadError
        'html5'
      end
    end

    # @api private
    # Ensure converted HTML includes a document title heading when header/footer is disabled.
    def self.ensure_document_title html_body, doctitle
      return html_body if doctitle.to_s.strip.empty?
      return html_body if html_body.match?(/<h1\b/i)

      "<h1>#{CGI.escapeHTML(doctitle.to_s)}</h1>\n\n#{html_body}"
    end

    private_class_method :process_block_content,
                         :resolve_html_backend,
                         :load_document_for_markdown_grade,
                         :ensure_document_title,
                         :normalize_extract_tagged_content_options,
                         :normalize_extract_tags,
                         :collect_tagged_content,
                         :normalize_mark_down_grade_options

    # Utilities for filtering and partitioning Asciidoctor document attributes.
    #
    # Separates user-defined ("custom") attributes from those injected by
    # Asciidoctor at parse time ("built-in").
    #
    # @example
    #   custom  = Sourcerer::AsciiDoc::AttributesFilter.user_attributes(doc)
    #   builtin = Sourcerer::AsciiDoc::AttributesFilter.builtin_attributes(doc)
    module AttributesFilter
      # Attribute keys injected by Asciidoctor at parse time.
      BUILTIN_ATTR_KEYS = (Asciidoctor::DEFAULT_ATTRIBUTES.keys + %w[
        asciidoctor asciidoctor-version
        attribute-missing attribute-undefined
        authorcount
        docdate docdatetime docdir docfile docfilesuffix docname doctime doctitle doctype docyear
        embedded
        htmlsyntax
        iconsdir
        localdate localdatetime localtime localyear
        max-include-depth
        notitle
        outfilesuffix
        stylesdir
        toc-position
        user-home
      ]).freeze

      BUILTIN_ATTR_PATTERNS = [
        /^backend(-|$)/,
        /^basebackend(-|$)/,
        /^doctype-/,
        /^filetype(-|$)/,
        /^safe-mode-/
      ].freeze

      module_function

      # Returns user-defined attributes, excluding Asciidoctor built-ins.
      #
      # @param doc [Asciidoctor::Document]
      # @return [Hash{String => String}]
      def user_attributes doc
        doc.attributes.reject do |k, _|
          BUILTIN_ATTR_KEYS.include?(k) ||
            BUILTIN_ATTR_PATTERNS.any? { |pat| pat.match?(k) }
        end
      end

      # Returns built-in Asciidoctor attributes injected at parse time.
      #
      # @param doc [Asciidoctor::Document]
      # @return [Hash{String => String}]
      def builtin_attributes doc
        doc.attributes.select do |k, _|
          BUILTIN_ATTR_KEYS.include?(k) ||
            BUILTIN_ATTR_PATTERNS.any? { |pat| pat.match?(k) }
        end
      end
    end
  end
end
