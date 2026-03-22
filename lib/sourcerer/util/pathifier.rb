# frozen_string_literal: true

require 'find'

module Sourcerer
  module Util
    # Classify an input string as file/dir/glob/missing and yield matching paths lazily.
    #
    # Not required internally; callers must require this file explicitly.
    module Pathifier
      GLOB_METACHARACTERS = /[*?\[\]{}]/

      # A small value object returned by +.match+.
      Result = Struct.new(:type, :input, :enum, keyword_init: true)

      # Classify +input+ and return a +Result+ with a lazy path enumerator.
      #
      # @param input           [String]  file path, directory path, or glob pattern
      # @param recursive       [Boolean] if dir, traverse recursively (default: +true+)
      # @param include_dirs    [Boolean] if dir traversal, also yield directory paths (default: +false+)
      # @param follow_symlinks [Boolean] follow symlink directories during recursal (default: +false+)
      # @return [Result]
      def self.match input, recursive: true, include_dirs: false, follow_symlinks: false
        type = classify(input)
        Result.new(
          type:  type,
          input: input,
          enum:  build_enum(
            type, input, recursive: recursive, include_dirs: include_dirs,
                                          follow_symlinks: follow_symlinks))
      end

      # Classify the input string without enumerating paths.
      #
      # @param input [String]
      # @return [:file, :dir, :glob, :missing]
      def self.classify input
        if File.file?(input)
          :file
        elsif File.directory?(input)
          :dir
        elsif GLOB_METACHARACTERS.match?(input)
          :glob
        else
          :missing
        end
      end
      private_class_method :classify

      def self.build_enum type, input, recursive:, include_dirs:, follow_symlinks:
        case type
        when :file
          Enumerator.new do |y|
            y << File.expand_path(input)
          end
        when :dir
          build_dir_enum(
            input, recursive: recursive, include_dirs: include_dirs,
                                 follow_symlinks: follow_symlinks)
        when :glob
          Enumerator.new do |y|
            Dir.glob(input) { |path| y << path }
          end
        else # :missing
          Enumerator.new { |_y| nil }
        end
      end
      private_class_method :build_enum

      def self.build_dir_enum input, recursive:, include_dirs:, follow_symlinks:
        abs = File.expand_path(input)
        if recursive
          Enumerator.new do |y|
            Find.find(abs) do |path|
              # Prune symlink directories unless follow_symlinks is set.
              if File.symlink?(path) && File.directory?(path) && !follow_symlinks
                Find.prune
              elsif File.directory?(path)
                y << path if include_dirs && path != abs
              else
                y << path
              end
            end
          end
        else
          Enumerator.new do |y|
            Dir.each_child(abs) do |name|
              path = File.join(abs, name)
              if File.directory?(path)
                y << path if include_dirs
              else
                y << path
              end
            end
          end
        end
      end
      private_class_method :build_dir_enum
    end
  end
end
