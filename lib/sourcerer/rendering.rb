# frozen_string_literal: true

require 'fileutils'
require_relative 'yaml'
require_relative 'asciidoc'

module Sourcerer
  # Rendering and output orchestration primitives.
  module Rendering
    # Renders a set of templates based on a configuration.
    #
    # @param templates_config [Array<Hash>] An array of template configurations.
    def self.render_templates templates_config
      render_outputs(templates_config)
    end

    # Renders templates or converter outputs based on a configuration.
    #
    # @param render_config [Array<Hash>] A list of render configurations.
    def self.render_outputs render_config
      return if render_config.nil? || render_config.empty?

      render_config.each do |render_entry|
        if render_entry[:converter]
          render_with_converter(render_entry)
          next
        end

        data_obj = render_entry[:key] || 'data'
        attrs_source = render_entry[:attrs]
        engine = render_entry[:engine] || 'liquid'

        render_template(
          render_entry[:template],
          render_entry[:data],
          render_entry[:out],
          data_object: data_obj,
          attrs_source: attrs_source,
          engine: engine)
      end
    end

    # Renders a single template with data.
    #
    # @param template_file [String] The path to the template file.
    # @param data_file [String] The path to the data file (YAML).
    # @param out_file [String] The path to the output file.
    # @param data_object [String] The name of the data object in the template.
    # @param includes_load_paths [Array<String>] Paths for Liquid includes.
    # @param attrs_source [String] The path to an AsciiDoc file for attributes.
    # @param engine [String] The template engine to use.
    def self.render_template template_file, data_file, out_file, **options
      supported_option_keys = %i[data_object includes_load_paths attrs_source engine]
      unknown_option_keys = options.keys - supported_option_keys
      raise ArgumentError, "unknown option(s): #{unknown_option_keys.join(', ')}" unless unknown_option_keys.empty?

      data_object = options.fetch(:data_object, 'data')
      includes_load_paths = options.fetch(:includes_load_paths, [])
      attrs_source = options[:attrs_source]
      engine = options.fetch(:engine, 'liquid')

      data = load_render_data(data_file, attrs_source)
      out_file = File.expand_path(out_file)
      FileUtils.mkdir_p(File.dirname(out_file))

      template_path = File.expand_path(template_file)
      template_content = File.read(template_path)

      context = {
        data_object => data,
        'include' => { data_object => data }
      }

      rendered = case engine.to_s
                 when 'erb' then render_erb(template_content, context)
                 when 'liquid' then render_liquid(template_file, template_content, context, includes_load_paths)
                 else raise ArgumentError, "Unsupported template engine: #{engine}"
                 end

      File.write(out_file, rendered)
    end

    # Renders output using a converter callable or converter constant name.
    #
    # @param render_entry [Hash] Render entry containing converter config.
    # @return [void]
    def self.render_with_converter render_entry
      data_file = render_entry[:data]
      out_file = render_entry[:out]
      raise ArgumentError, 'render entry missing :data' unless data_file
      raise ArgumentError, 'render entry missing :out' unless out_file

      data = load_render_data(data_file, render_entry[:attrs])
      converter = resolve_converter(render_entry[:converter])
      rendered = converter.call(data, render_entry)
      raise ArgumentError, 'converter returned non-string output' unless rendered.is_a?(String)

      out_file = File.expand_path(out_file)
      FileUtils.mkdir_p(File.dirname(out_file))
      File.write(out_file, rendered)
    end

    # @api private
    # Loads render data with optional AsciiDoc attributes.
    #
    # @param data_file [String] Path to YAML data file.
    # @param attrs_source [String, nil] Path to AsciiDoc attributes source.
    # @return [Hash]
    def self.load_render_data data_file, attrs_source
      if attrs_source
        attrs = Sourcerer::AsciiDoc.load_attributes(attrs_source)
        Sourcerer::Yaml.load_with_attributes(data_file, attrs)
      else
        Sourcerer::Yaml.load_with_tags(data_file)
      end
    end

    # @api private
    # Resolves a converter from callable or constant-name forms.
    #
    # @param converter [#call, String]
    # @return [#call]
    def self.resolve_converter converter
      return converter if converter.respond_to?(:call)
      return Object.const_get(converter) if converter.is_a?(String)

      raise ArgumentError, "Unsupported converter: #{converter.inspect}"
    end

    # @api private
    # Render ERB template content with context.
    #
    # @param template_content [String]
    # @param context [Hash]
    # @return [String]
    def self.render_erb template_content, context
      require 'erb'
      ERB.new(template_content, trim_mode: '-').result_with_hash(context)
    end

    # @api private
    # Render Liquid template content using the Sourcerer Jekyll runtime.
    #
    # @param template_file [String]
    # @param template_content [String]
    # @param context [Hash]
    # @param includes_load_paths [Array<String>]
    # @return [String]
    def self.render_liquid template_file, template_content, context, includes_load_paths
      require_relative 'jekyll'
      require_relative 'jekyll/liquid/filters'
      require_relative 'jekyll/liquid/tags'
      require 'liquid' unless defined?(Liquid::Template)
      Sourcerer::Jekyll.initialize_liquid_runtime

      fallback_templates_dir = File.expand_path('.', Dir.pwd)
      template_dir = File.dirname(File.expand_path(template_file))
      template_parent_dir = File.dirname(template_dir)

      paths = if includes_load_paths.any?
                includes_load_paths
              else
                [template_parent_dir, template_dir, fallback_templates_dir]
              end

      site = Sourcerer::Jekyll::Bootstrapper.fake_site(
        includes_load_paths: paths,
        plugin_dirs: [])

      file_system = Sourcerer::Jekyll::Liquid::FileSystem.new(paths)

      template = Liquid::Template.parse(template_content)
      options = {
        registers: {
          site: site,
          file_system: file_system
        }
      }
      template.render(context, options)
    end

    # Render a Liquid template string directly with a data hash.
    #
    # Unlike {.render_template}, this method accepts an in-memory string and
    # a plain Ruby Hash rather than paths to data files.  Suitable for
    # rendering individual block content (e.g. in Sync/Cast) without setting
    # up a full template pipeline.
    #
    # Keys in `data` are stringified to satisfy Liquid's string-key contract.
    # Nested key stringification is shallow; callee is responsible for deeper
    # transformations if required.
    #
    # The Jekyll/Liquid runtime is initialized before rendering so that any
    # custom filters or tags registered elsewhere in Sourcerer are available.
    #
    # @param content [String] Liquid template source.
    # @param data [Hash] Variables available to the template.
    # @return [String] Rendered output.
    def self.render_liquid_string content, data
      require_relative 'jekyll'
      require_relative 'jekyll/liquid/filters'
      require_relative 'jekyll/liquid/tags'
      require 'liquid' unless defined?(Liquid::Template)
      Sourcerer::Jekyll.initialize_liquid_runtime

      template = Liquid::Template.parse(content)
      template.render(data.transform_keys(&:to_s))
    end

    private_class_method :load_render_data,
                         :resolve_converter,
                         :render_erb,
                         :render_liquid
  end
end
