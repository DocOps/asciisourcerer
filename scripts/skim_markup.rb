#!/usr/bin/env ruby
# frozen_string_literal: true

#
# CLI wrapper for Sourcerer::SourceSkim.
# Produces structured skims of AsciiDoc and Markdown source files.
#
# Format is auto-detected from file extension (.adoc, .md, .markdown).
# Override with --adoc or --markdown when the extension is absent or misleading.
#
# WARNING: This script is only minimally tested and NOT officially supported.
#          It may be altered backward-incompatibly, deprecated, or even dropped.
#          Use it as an example but do not rely on it in production.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'json'
require 'optparse'
require 'yaml'
require 'sourcerer'
require 'sourcerer/util/list_amend'
require 'sourcerer/util/pathifier'

ADOC_EXTS     = %w[.adoc].freeze
MARKDOWN_EXTS = %w[.md .markdown].freeze
ALL_EXTS      = (ADOC_EXTS + MARKDOWN_EXTS).freeze

options = {
  forms:       [],
  output:      nil,
  categories:  nil,
  attributes:  {},
  syntax:      nil,
  force_fmt:   nil
}

default_cats = Sourcerer::SourceSkim::DEFAULT_CATEGORIES.map(&:to_s)

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} PATH [options]\n\n  " \
                "PATH  A file path, directory (recursively searched for\n        " \
                "*.adoc, *.md, *.markdown), or a glob pattern.\n"

  opts.on('--tree', 'Include a nested section tree in output (sections_tree)') do
    options[:forms] << :tree
  end
  opts.on('--flat', 'Include a flat section list in output (sections_flat)') do
    options[:forms] << :flat
  end
  opts.on(
    '--categories SPEC',
    'AsciiDoc only. Categories to include. Comma/space-separated list.',
    'Prefix tokens with + or - to amend defaults; otherwise replaces them.',
    "Default: #{default_cats.join(',')}") do |spec|
    options[:categories] = spec
  end
  opts.on('--json', 'Force JSON output (overrides default YAML-to-stdout)') do
    options[:syntax] = :json
  end
  opts.on('--yaml', 'Force YAML output (overrides default JSON-to-file)') do
    options[:syntax] = :yaml
  end
  opts.on(
    '-a', '--attribute KEY=VALUE',
    'AsciiDoc only. Set an Asciidoctor attribute (repeatable), e.g. -a env=prod') do |pair|
    key, value = pair.split('=', 2)
    options[:attributes][key] = value || ''
  end
  opts.on('--adoc', 'Force all paths to be treated as AsciiDoc') do
    options[:force_fmt] = :asciidoc
  end
  opts.on('--markdown', 'Force all paths to be treated as Markdown') do
    options[:force_fmt] = :markdown
  end
  opts.on(
    '-o', '--output FILE',
    'Write output to FILE; format auto-detected from extension (.json/.yml/.yaml)') do |file|
    options[:output] = file
  end
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
end
parser.parse!

if ARGV.empty?
  warn "Error: PATH argument is required\n\n#{parser.help}"
  exit 1
end

# Resolve categories (AsciiDoc only) using ListAmend.
resolved_cats   = Sourcerer::Util::ListAmend.apply(default_cats, options[:categories])
adoc_categories = resolved_cats.map(&:to_sym)

# Resolve input path to an enumerator of matching paths using Pathifier.
path   = ARGV.first
result = Sourcerer::Util::Pathifier.match(path)

all_paths = if result.type == :dir
              result.enum.select { |p| ALL_EXTS.include?(File.extname(p).downcase) }
            else
              result.enum.to_a
            end

if all_paths.empty?
  warn "No markup files found for: #{path}"
  exit 1
end

# Warn if --categories or -a were given but no AsciiDoc files are in the set.
if options[:force_fmt] == :markdown || all_paths.none? { |p| ADOC_EXTS.include?(File.extname(p).downcase) }
  warn 'Warning: --categories has no effect because no AsciiDoc files are being skimmed.' if options[:categories]
  unless options[:attributes].empty?
    warn 'Warning: --attribute/-a has no effect because no AsciiDoc files are being skimmed.'
  end
end

user_forms = options[:forms].empty? ? nil : options[:forms]

results = {}
all_paths.each do |fp|
  results[fp] = Sourcerer::SourceSkim.skim_file(
    fp,
    forms:      user_forms,
    format:     options[:force_fmt],
    categories: adoc_categories.empty? ? nil : adoc_categories,
    attributes: options[:attributes])
end

# Convert symbol keys to strings for portable output in both formats.
portable = JSON.parse(JSON.generate(results))

ext = File.extname(options[:output].to_s).downcase
ext_syntax = case ext
             when '.json' then :json
             when '.yml', '.yaml' then :yaml
             end

if options[:syntax] && ext_syntax && options[:syntax] != ext_syntax
  if options[:syntax] == :yaml
    warn "Error: --yaml conflicts with #{ext} output file (YAML is not valid JSON)."
    exit 1
  else
    warn "Warning: writing JSON to a #{ext} file (JSON is valid YAML, but consider .json extension)."
  end
end

syntax = options[:syntax] || ext_syntax || (options[:output] ? :json : :yaml)

if options[:output]
  content = syntax == :yaml ? portable.to_yaml : JSON.pretty_generate(portable)
  File.write(options[:output], content)
  warn "Skimmed #{all_paths.size} file(s) written to #{options[:output]}"
else
  puts(syntax == :json ? JSON.pretty_generate(portable) : portable.to_yaml)
end
