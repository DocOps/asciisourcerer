# frozen_string_literal: true

# AsciiSourcerer is the primary entry point for the asciisourcerer gem.
# It provides an alias to the internal Sourcerer module to avoid namespace
# conflicts with the unrelated 'sourcerer' gem on RubyGems.org.

require_relative 'sourcerer'

# Primary module alias for the asciisourcerer gem
module AsciiSourcerer
  # Transparently delegate all constants and methods to Sourcerer
  def self.const_missing name
    Sourcerer.const_get(name)
  end

  def self.method_missing(method, ...)
    Sourcerer.send(method, ...)
  end

  def self.respond_to_missing? method, include_private = false
    Sourcerer.respond_to?(method, include_private) || super
  end
end

# Make all Sourcerer submodules available through AsciiSourcerer
AsciiSourcerer::VERSION = Sourcerer::VERSION
AsciiSourcerer::AsciiDoc = Sourcerer::AsciiDoc
AsciiSourcerer::Yaml = Sourcerer::Yaml
AsciiSourcerer::Rendering = Sourcerer::Rendering
AsciiSourcerer::Builder = Sourcerer::Builder
AsciiSourcerer::MarkDownGrade = Sourcerer::MarkDownGrade
AsciiSourcerer::Jekyll = Sourcerer::Jekyll
AsciiSourcerer::Sync = Sourcerer::Sync
