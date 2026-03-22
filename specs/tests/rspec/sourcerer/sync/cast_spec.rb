# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../../spec_helper'
require_relative '../../../../../lib/sourcerer/sync'

RSpec.describe Sourcerer::Sync::Cast do
  let(:fixtures_dir) { File.expand_path('../../../fixtures/sync', __dir__) }
  let(:prime_path) { File.join(fixtures_dir, 'prime_template.md') }
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  def tmp_copy source_filename
    src = File.join(fixtures_dir, source_filename)
    dest = File.join(tmpdir, source_filename)
    FileUtils.cp(src, dest)
    dest
  end

  def tmp_file filename, content
    path = File.join(tmpdir, filename)
    File.write(path, content)
    path
  end

  # ---------------------------------------------------------------------------
  describe '.sync' do
    context 'when target blocks match the prime exactly' do
      it 'applies no changes' do
        target = tmp_copy('target_in_sync.md')
        result = described_class.sync(prime_path, target)
        expect(result.applied_changes).to be_empty
        expect(result.errors).to be_empty
      end

      it 'leaves the file unchanged on disk' do
        target = tmp_copy('target_in_sync.md')
        original = File.read(target)
        described_class.sync(prime_path, target)
        expect(File.read(target)).to eq(original)
      end
    end

    context 'when target blocks are stale' do
      it 'reports the changed block names' do
        target = tmp_copy('target_needs_sync.md')
        result = described_class.sync(prime_path, target)
        expect(result.applied_changes).to contain_exactly('universal-intro', 'universal-footer')
      end

      it 'writes updated content to the target file' do
        target = tmp_copy('target_needs_sync.md')
        described_class.sync(prime_path, target)
        content = File.read(target)
        expect(content).to include("This content is managed centrally.\n")
        expect(content).to include("Copyright (c) 2025 DocOps Lab.\n")
      end

      it 'preserves local (non-canonical) content unchanged' do
        target = tmp_copy('target_needs_sync.md')
        described_class.sync(prime_path, target)
        content = File.read(target)
        expect(content).to include('Local content that must not be touched')
        expect(content).to include('Project-specific footer text.')
      end

      it 'keeps the tag marker lines intact' do
        target = tmp_copy('target_needs_sync.md')
        described_class.sync(prime_path, target)
        content = File.read(target)
        expect(content).to include('<!-- tag::universal-intro[] -->')
        expect(content).to include('<!-- end::universal-intro[] -->')
      end

      it 'produces a non-empty diff' do
        target = tmp_copy('target_needs_sync.md')
        result = described_class.sync(prime_path, target)
        expect(result.diff).not_to be_nil
        expect(result.diff).not_to be_empty
      end
    end

    context 'when dry_run is true' do
      it 'returns an empty applied_changes list' do
        target = tmp_copy('target_needs_sync.md')
        File.read(target)
        result = described_class.sync(prime_path, target, dry_run: true)
        expect(result.applied_changes).to be_empty
      end

      it 'does not modify the file on disk' do
        target = tmp_copy('target_needs_sync.md')
        original = File.read(target)
        described_class.sync(prime_path, target, dry_run: true)
        expect(File.read(target)).to eq(original)
      end

      it 'still provides a diff showing the pending changes' do
        target = tmp_copy('target_needs_sync.md')
        result = described_class.sync(prime_path, target, dry_run: true)
        expect(result.diff).not_to be_nil
      end
    end

    context 'when target is missing a canonical block' do
      it 'emits a warning' do
        target_text = <<~MD
          # No universal-intro here

          <!-- tag::universal-footer[] -->
          Footer.
          <!-- end::universal-footer[] -->
        MD
        target = tmp_file('target_missing_block.md', target_text)
        result = described_class.sync(prime_path, target)
        expect(result.warnings).to include(match(/universal-intro.*not found/i))
      end
    end

    context 'when target has a non-canonical alternate block' do
      it 'suppresses the missing canonical block warning' do
        target_text = <<~MD
          <!-- tag::local-intro[] -->
          Local intro.
          <!-- end::local-intro[] -->

          <!-- tag::universal-footer[] -->
          Footer.
          <!-- end::universal-footer[] -->
        MD
        target = tmp_file('target_with_alternate.md', target_text)
        result = described_class.sync(prime_path, target)
        expect(result.warnings).not_to include(match(/universal-intro/))
      end
    end

    context 'when target has a canonical block not in the prime' do
      it 'emits a warning for the orphaned block' do
        target_text = <<~MD
          <!-- tag::universal-intro[] -->
          Intro.
          <!-- end::universal-intro[] -->

          <!-- tag::universal-footer[] -->
          Footer.
          <!-- end::universal-footer[] -->

          <!-- tag::universal-orphan[] -->
          Orphan content.
          <!-- end::universal-orphan[] -->
        MD
        target = tmp_file('target_orphan.md', target_text)
        result = described_class.sync(prime_path, target)
        expect(result.warnings).to include(match(/universal-orphan.*not found/i))
      end
    end

    context 'when target has duplicate canonical blocks' do
      it 'returns an error and does not write the file' do
        target_text = <<~MD
          <!-- tag::universal-intro[] -->
          First intro.
          <!-- end::universal-intro[] -->

          <!-- tag::universal-intro[] -->
          Duplicate intro.
          <!-- end::universal-intro[] -->
        MD
        target = tmp_file('target_dup.md', target_text)
        original = File.read(target)
        result = described_class.sync(prime_path, target)
        expect(result.errors).not_to be_empty
        expect(File.read(target)).to eq(original)
      end
    end

    context 'with Liquid data' do
      it 'renders Liquid variables in canonical block content' do
        prime = tmp_file('prime_liq.md', <<~MD)
          <!-- tag::universal-intro[] -->
          This is {{ name }} version {{ version }}.
          <!-- end::universal-intro[] -->
        MD
        target_text = <<~MD
          <!-- tag::universal-intro[] -->
          OLD content.
          <!-- end::universal-intro[] -->
        MD
        target = tmp_file('target_liq.md', target_text)
        described_class.sync(prime, target, data: { 'name' => 'MyGem', 'version' => '0.2.0' })
        content = File.read(target)
        expect(content).to include('This is MyGem version 0.2.0.')
      end
    end

    context 'when using the convenience wrapper Sourcerer::Sync.sync' do
      it 'delegates to Cast.sync' do
        target = tmp_copy('target_needs_sync.md')
        result = Sourcerer::Sync.sync(prime_path, target)
        expect(result).to be_a(described_class::CastResult)
        expect(result.applied_changes).not_to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe '.init' do
    it 'creates the target file' do
      target = File.join(tmpdir, 'new_repo', 'AGENTS.md')
      described_class.init(prime_path, target)
      expect(File.exist?(target)).to be true
    end

    it 'writes the prime template content to the target' do
      target = File.join(tmpdir, 'AGENTS.md')
      described_class.init(prime_path, target)
      expect(File.read(target)).to eq(File.read(prime_path))
    end

    it 'renders Liquid variables when data is provided' do
      liquid_prime = File.join(fixtures_dir, 'prime_liquid.md')
      target = File.join(tmpdir, 'README.md')
      described_class.init(liquid_prime, target, data: { 'name' => 'TestGem', 'version' => '1.0.0' })
      content = File.read(target)
      expect(content).to include('This gem is called TestGem and is at version 1.0.0.')
    end

    it 'creates parent directories as needed' do
      target = File.join(tmpdir, 'deep', 'nested', 'dir', 'output.md')
      described_class.init(prime_path, target)
      expect(File.exist?(target)).to be true
    end

    context 'when dry_run is true' do
      it 'does not create the target file' do
        target = File.join(tmpdir, 'dry_run_output.md')
        described_class.init(prime_path, target, dry_run: true)
        expect(File.exist?(target)).to be false
      end

      it 'returns rendered content in diff field' do
        target = File.join(tmpdir, 'dry_run_output.md')
        result = described_class.init(prime_path, target, dry_run: true)
        expect(result.diff).to eq(File.read(prime_path))
      end
    end

    context 'when using the convenience wrapper Sourcerer::Sync.init' do
      it 'delegates to Cast.init' do
        target = File.join(tmpdir, 'conv_init.md')
        result = Sourcerer::Sync.init(prime_path, target)
        expect(result).to be_a(described_class::CastResult)
        expect(File.exist?(target)).to be true
      end
    end
  end
end
