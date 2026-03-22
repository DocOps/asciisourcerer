#!/usr/bin/env ruby
#
# frozen_string_literal: true

#
# CLI wrapper for Sourcerer::SourceSkim.
# Produces structured skims of AsciiDoc source files.
#
# Default output: YAML to stdout, JSON to file when -o/--output is given.
# File extension auto-detection: .json -> JSON, .yml/.yaml -> YAML, no/other extension -> JSON.
# Override with --yaml or --json
# Usage:
#   ruby scripts/skim_asciidoc.rb PATH [--tree] [--flat] [--categories CATS] [--json|--yaml] [-o FILE]
#
# PATH may be a file, directory (traversed recursively for *.adoc), or a glob pattern.
#
# --categories accepts a comma/space-separated list of category names.
# Prefix with + or - to amend the default category set rather than replacing it.
# Example: --categories "-admonitions,+quotes"
#
# WARNING: These script is only minimally tested NOT officially supported.
#          It may be altered backward-incompatibly, deprecated, or even dropped.
#          Use it as an example but do not rely on it in production.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'json'
require 'optparse'
require 'yaml'
require 'sourcerer'
require 'sourcerer/util/list_amend'
require 'sourcerer/util/pathifier'

options = { forms: [], output: nil, categories: nil, attributes: {}, syntax: nil }

default_cats = Sourcerer::SourceSkim::DEFAULT_CATEGORIES.map(&:to_s)

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} PATH [options]\n\n  " \
                "PATH  A file path, directory (recursively searched for *.adoc),\n        " \
                "or a glob pattern (e.g. 'docs/**/*.adoc')\n"

  opts.on('--tree', 'Include a nested section tree in output (sections_tree) [default]') do
    options[:forms] << :tree
  end
  opts.on('--flat', 'Include a flat section list in output (sections_flat)') do
    options[:forms] << :flat
  end
  opts.on(
    '--categories SPEC',
    'Categories to include. Comma/space-separated list.',
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
    'Set an Asciidoctor attribute (repeatable), e.g. -a env=prod') do |pair|
    key, value = pair.split('=', 2)
    options[:attributes][key] = value || ''
  end
  opts.on('-o', '--output FILE', 'Write output to FILE; format auto-detected from extension (.json/.yml/.yaml)') do |file|
    options[:output] = file
  end
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
end
parser.parse!

options[:forms] = [:tree] if options[:forms].empty?

if ARGV.empty?
  warn "Error: PATH argument is required\n\n#{parser.help}"
  exit 1
end

# Resolve categories using ListAmend: supports fixed-list and +/- amendment modes.
resolved_cats = Sourcerer::Util::ListAmend.apply(default_cats, options[:categories])
options[:categories] = resolved_cats.map(&:to_sym)

# Resolve input path to an enumerator of matching paths using Pathifier.
path   = ARGV.first
result = Sourcerer::Util::Pathifier.match(path)

file_paths = if result.type == :dir
               result.enum.select { |p| p.end_with?('.adoc') }
             else
               result.enum.to_a
             end

if file_paths.empty?
  warn "No .adoc files found for: #{path}"
  exit 1
end

results = {}
file_paths.each do |fp|
  results[fp] = Sourcerer::SourceSkim.skim_file(
    fp,
    forms:      options[:forms],
    categories: options[:categories].empty? ? nil : options[:categories],
    attributes: options[:attributes])
end

# Convert symbol keys to strings for portable output in both formats.
portable = JSON.parse(JSON.generate(results))

ext = File.extname(options[:output].to_s).downcase
ext_syntax = case ext
             when '.json'        then :json
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
  warn "Skimmed #{file_paths.size} file(s) written to #{options[:output]}"
else
  puts(syntax == :json ? JSON.pretty_generate(portable) : portable.to_yaml)
end
