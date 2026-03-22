#!/usr/bin/env ruby
#
# frozen_string_literal: true

#
# CLI wrapper for Sourcerer::SourceSkim.
# Produces structured skims of AsciiDoc source files.
#
# Default output: YAML to stdout (symbol keys converted to strings).
# With -o/--output FILE: pretty-printed JSON written to FILE.
#
# Usage:
#   ruby scripts/skim_asciidoc.rb PATH [--tree] [--flat] [--categories CATS] [-o FILE]
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

options = { forms: [], output: nil, categories: nil, attributes: {} }

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
  opts.on(
    '-a', '--attribute KEY=VALUE',
    'Set an Asciidoctor attribute (repeatable), e.g. -a env=prod') do |pair|
    key, value = pair.split('=', 2)
    options[:attributes][key] = value || ''
  end
  opts.on('-o', '--output FILE', 'Write JSON to FILE; omit for YAML to stdout') do |file|
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

if options[:output]
  File.write(options[:output], JSON.pretty_generate(portable))
  warn "Skimmed #{file_paths.size} file(s) written to #{options[:output]}"
else
  puts portable.to_yaml
end
