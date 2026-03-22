#!/usr/bin/env ruby
#
# frozen_string_literal: true

#
# CLI script for converting AsciiDoc files to Markdown.
# Uses Sourcerer::AsciiDoc.mark_down_grade via the MarkDownGrade converter.
#
# Usage:
#   ruby scripts/mark_down_grade.rb FILE|DIR|GLOB [options]
#
# Example:
#   ruby scripts/mark_down_grade.rb docs/ -o out/ --gh-flavored
#
# WARNING: These script is only minimally tested NOT officially supported.
#          It may be altered backward-incompatibly, deprecated, or even dropped.
#          Use it as an example but do not rely on it in production.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'optparse'
require 'fileutils'
require 'sourcerer'
require 'sourcerer/util/pathifier'

options = {
  output: nil,
  attributes: {},
  gh_flavored: false,
  html5s: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} FILE|DIR|GLOB [options]"

  opts.on('-o', '--output PATH', 'Output directory (for DIR/GLOB) or file (for FILE source)') do |path|
    options[:output] = path
  end

  opts.on('-a', '--attribute KEY=VALUE', 'Set an Asciidoctor attribute (repeatable)') do |pair|
    key, value = pair.split('=', 2)
    options[:attributes][key] = value || ''
  end

  opts.on('--gh-flavored', 'Enable GitHub-flavored Markdown') do
    options[:gh_flavored] = true
  end

  opts.on('--html5s', 'Use HTML5s backend for interim conversion') do
    options[:html5s] = true
  end

  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
end

begin
  parser.parse!
rescue OptionParser::InvalidOption => e
  warn "Error: #{e.message}"
  warn parser.help
  exit 1
end

if ARGV.empty?
  warn "Error: PATH argument is required\n\n#{parser.help}"
  exit 1
end

path = ARGV.first
result = Sourcerer::Util::Pathifier.match(path)

file_paths = case result.type
             when :dir
               result.enum.select { |p| p.to_s.end_with?('.adoc') }.to_a
             when :file
               [path]
             when :glob
               result.enum.to_a
             else
               []
             end

if file_paths.empty?
  warn "No .adoc files found for: #{path}"
  exit 1
end

# Define the markdown converter closure
markdown_converter = proc do |html, markdown_options|
  Sourcerer::MarkDownGrade.convert_html(html, markdown_options || {})
end

grade_options = {
  markdown_converter: markdown_converter,
  attributes: options[:attributes],
  backend: options[:html5s] ? 'asciidoctor-html5s' : 'html5',
  markdown_options: {
    github_flavored: options[:gh_flavored]
  }
}

file_paths.each do |source_path|
  target_path = nil

  if options[:output]
    if result.type == :file
      if options[:output].end_with?('.md')
        target_path = options[:output]
      else
        # If output is a directory for a single file, put it there with .md extension
        FileUtils.mkdir_p(options[:output])
        target_path = File.join(options[:output], File.basename(source_path).sub(/\.adoc$/, '.md'))
      end
    else
      # DIR or GLOB: output must be a directory
      FileUtils.mkdir_p(options[:output])
      # Maintain relative structure if possible, but pathifier gives abs or direct paths.
      # For simplicity, we'll flatten into the output dir if it's a glob or dir.
      target_path = File.join(options[:output], File.basename(source_path).sub(/\.adoc$/, '.md'))
    end
  end

  begin
    Sourcerer::AsciiDoc.mark_down_grade(source_path, target_path, **grade_options)

    if target_path
      warn "Converted: #{source_path} -> #{target_path}"
    else
      # If no output path, we need to handle the result hash if we wanted to print to stdout.
      # mark_down_grade returns a hash.
      result_hash = Sourcerer::AsciiDoc.mark_down_grade(source_path, nil, **grade_options)
      puts result_hash[:markdown]
    end
  rescue StandardError => e
    warn "Error converting #{source_path}: #{e.message}"
    warn e.backtrace.join("\n") if $DEBUG
  end
end
