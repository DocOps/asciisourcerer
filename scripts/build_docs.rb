#!/usr/bin/env ruby
#
# frozen_string_literal: true

#
# Regenerates the reference docs described by specs/data/docs-manifest.yml
# and locally commits them to an orphan `documentation` branch, so
# downstream consumers who don't install the gem can pull them directly
# (e.g. via raw.githubusercontent.com).
#
# This script only commits locally -- it does not push. Review the result
# with `git log documentation` / `git show documentation`, then push
# yourself when ready:
#
#   git push -f origin documentation
#
# Usage:
#   ruby scripts/build_docs.rb

require 'yaml'
require 'fileutils'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))
require 'sourcerer'

MANIFEST_PATH = File.join(ROOT, 'specs/data/docs-manifest.yml')
BRANCH = 'documentation'

# Renders every entry in the docs manifest into publish_dir/partials/,
# reusing the same Sourcerer::Rendering pipeline as the `generate:docs`
# Rake task, but writing to a scratch location instead of the gem's own
# lib/sourcerer/_docs/partials/.
def render_docs_to publish_dir
  manifest = YAML.safe_load_file(MANIFEST_PATH, permitted_classes: [Date, Time])
  entries = manifest['docs'] || []

  entries.each do |entry|
    render_entry = entry.transform_keys(&:to_sym)
    out_basename = File.basename(render_entry[:out])
    out = File.join(publish_dir, 'partials', out_basename)

    render_entry[:template] = File.expand_path(render_entry[:template], ROOT)
    render_entry[:data] = File.expand_path(render_entry[:data], ROOT)
    render_entry[:out] = out

    puts "Rendering #{render_entry[:name] || out_basename} -> #{out}"
    Sourcerer::Rendering.render_outputs([render_entry])
  end
end

def run! *cmd, chdir: Dir.pwd
  system(*cmd, chdir: chdir, exception: true)
end

# Runs a git command with core.hooksPath overridden for this invocation
# only, via `git -c`. This worktree only ever holds generated output (no
# Rakefile/Gemfile by design), so the repo's own commit hooks -- which
# assume a full dev environment -- can't run here. A plain `git config
# core.hooksPath ...` would write to the repository's shared config
# (worktrees share it by default) and disable hooks repo-wide, including
# in the main working tree -- `-c` scopes the override to this process
# only, touching no file.
def worktree_git *cmd, chdir:
  run!('git', '-c', "core.hooksPath=#{File::NULL}", *cmd, chdir: chdir)
end

# Like Dir.mktmpdir, but tolerates the directory already being gone by the
# time the block finishes (e.g. `git worktree remove` deletes it for us).
def with_scratch_dir
  dir = Dir.mktmpdir
  yield dir
ensure
  FileUtils.remove_entry(dir) if dir && File.exist?(dir)
end

def branch_exists? name
  system('git', 'show-ref', '--verify', '--quiet', "refs/heads/#{name}", chdir: ROOT)
end

# Builds/updates the `documentation` branch in a throwaway worktree so the
# current working tree and index are never touched.
def commit_to_documentation_branch publish_dir
  with_scratch_dir do |worktree_dir|
    run!('git', 'worktree', 'add', '--detach', worktree_dir, chdir: ROOT)

    begin
      checkout_args = branch_exists?(BRANCH) ? ['checkout', BRANCH] : ['checkout', '--orphan', BRANCH]
      worktree_git(*checkout_args, chdir: worktree_dir)

      tracked = `git -C #{worktree_dir} ls-files`.split("\n")
      worktree_git('rm', '-rf', '--quiet', '.', chdir: worktree_dir) unless tracked.empty?

      FileUtils.cp_r(Dir.glob(File.join(publish_dir, '*')), worktree_dir)
      worktree_git('add', '-A', chdir: worktree_dir)

      if `git -C #{worktree_dir} status --porcelain`.strip.empty?
        puts 'No changes to publish; documentation branch already up to date.'
      else
        worktree_git('commit', '-m', 'docs: Regenerate Liquid filter reference docs', chdir: worktree_dir)
        puts "Committed update to local '#{BRANCH}' branch (not pushed)."
      end
    ensure
      run!('git', 'worktree', 'remove', '--force', worktree_dir, chdir: ROOT)
    end
  end
end

Dir.mktmpdir do |publish_dir|
  render_docs_to(publish_dir)
  commit_to_documentation_branch(publish_dir)
end
