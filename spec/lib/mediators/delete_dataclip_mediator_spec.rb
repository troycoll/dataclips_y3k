# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/mediators/delete_dataclip_mediator'

RSpec.describe DeleteDataclipMediator do
  let(:slug) { 'test-dataclip-123' }
  include_examples 'a dataclip mock'
  let(:existing_dataclip) { mock_dataclip }

  let(:mock_table) { double('dataclips_table') }

  before do
    allow(DB).to receive(:[]).with(:dataclips).and_return(mock_table)
  end

  include_examples 'a mediator class method', DeleteDataclipMediator, 'test-slug'

  describe '#initialize' do
    it 'initializes with slug' do
      mediator = described_class.new(slug)
      expect(mediator.send(:slug)).to eq(slug)
    end

    it 'initializes with slug and params' do
      mediator = described_class.new(slug, { some: 'param' })
      expect(mediator.send(:slug)).to eq(slug)
    end

    it 'strips whitespace from slug' do
      mediator = described_class.new('  test-dataclip-123  ')
      expect(mediator.send(:slug)).to eq('test-dataclip-123')
    end

    it 'handles nil slug gracefully' do
      mediator = described_class.new(nil)
      expect(mediator.send(:slug)).to be_nil
    end
  end

  describe '#call' do
    context 'with valid slug and existing dataclip' do
      before do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: existing_dataclip))
      end

      it 'returns self' do
        allow_any_instance_of(described_class).to receive(:delete_dataclip_record)
        mediator = described_class.new(slug)
        result = mediator.call
        expect(result).to eq(mediator)
      end

      it 'is successful' do
        allow_any_instance_of(described_class).to receive(:delete_dataclip_record)
        mediator = described_class.new(slug)
        mediator.call
        expect(mediator.success?).to be true
      end

      it 'calls delete_dataclip_record' do
        mediator = described_class.new(slug)
        expect(mediator).to receive(:delete_dataclip_record)
        mediator.call
      end
    end

    context 'with non-existent dataclip' do
      before do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: nil))
      end

      it 'does not call delete_dataclip_record when dataclip does not exist' do
        mediator = described_class.new(slug)
        expect(mediator).not_to receive(:delete_dataclip_record)
        mediator.call
      end

      it 'is not successful when dataclip does not exist' do
        mediator = described_class.new(slug)
        mediator.call
        expect(mediator.success?).to be false
        expect(mediator.errors).to include('Dataclip not found')
      end
    end

    context 'with empty or nil slug' do
      it 'does not call delete_dataclip_record when slug is empty' do
        mediator = described_class.new('')
        expect(mediator).not_to receive(:delete_dataclip_record)
        mediator.call
      end

      it 'is not successful when slug is empty' do
        mediator = described_class.new('')
        mediator.call
        expect(mediator.success?).to be false
        expect(mediator.errors).to include('Slug is required')
      end

      it 'is not successful when slug is nil' do
        mediator = described_class.new(nil)
        mediator.call
        expect(mediator.success?).to be false
        expect(mediator.errors).to include('Slug is required')
      end

      it 'is not successful when slug is whitespace only' do
        mediator = described_class.new('   ')
        mediator.call
        expect(mediator.success?).to be false
        expect(mediator.errors).to include('Slug is required')
      end
    end
  end

  describe '#deleted_dataclip' do
    it 'exposes the deleted_dataclip attribute' do
      mediator = described_class.new(slug)
      expect(mediator).to respond_to(:deleted_dataclip)
    end
  end

  describe 'validation' do
    describe 'slug validation' do
      it 'requires slug to be present' do
        mediator = described_class.new('')
        mediator.call
        expect(mediator.errors).to include('Slug is required')
      end

      it 'checks dataclip existence when slug is present' do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: nil))
        mediator = described_class.new(slug)
        mediator.call
        expect(mediator.errors).to include('Dataclip not found')
      end

      it 'does not check dataclip existence when slug is empty' do
        expect(mock_table).not_to receive(:where)
        mediator = described_class.new('')
        mediator.call
      end
    end

    describe 'dataclip existence validation' do
      it 'adds error when dataclip does not exist' do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: nil))
        mediator = described_class.new(slug)
        mediator.call
        expect(mediator.errors).to include('Dataclip not found')
      end

      it 'does not add error when dataclip exists' do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: existing_dataclip))
        allow_any_instance_of(described_class).to receive(:delete_dataclip_record)
        mediator = described_class.new(slug)
        mediator.call
        expect(mediator.errors).not_to include('Dataclip not found')
      end
    end
  end

  describe 'database operations' do
    let(:mock_where_clause) { double('where_clause') }

    before do
      allow(mock_table).to receive(:where).with(slug: slug).and_return(mock_where_clause)
      allow(mock_where_clause).to receive(:first).and_return(existing_dataclip)
    end

    describe '#delete_dataclip_record' do
      it 'stores the dataclip before deletion' do
        expect(mock_where_clause).to receive(:delete)
        mediator = described_class.new(slug)
        mediator.call
        expect(mediator.deleted_dataclip).to eq(existing_dataclip)
      end

      it 'creates a copy of the dataclip record' do
        expect(mock_where_clause).to receive(:delete)
        mediator = described_class.new(slug)
        mediator.call

        # Verify it's a copy, not the same object
        expect(mediator.deleted_dataclip).to eq(existing_dataclip)
        expect(mediator.deleted_dataclip).not_to be(existing_dataclip)
      end

      it 'deletes the dataclip from the database' do
        expect(mock_where_clause).to receive(:delete)
        mediator = described_class.new(slug)
        mediator.call
      end

      it 'is successful after deletion' do
        expect(mock_where_clause).to receive(:delete)
        mediator = described_class.new(slug)
        mediator.call
        expect(mediator.success?).to be true
      end
    end

    describe 'error handling' do
      before do
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip)
      end

      it 'handles Sequel::DatabaseError' do
        error = Sequel::DatabaseError.new('Database connection failed')
        expect(mock_where_clause).to receive(:delete).and_raise(error)

        mediator = described_class.new(slug)
        mediator.call

        expect(mediator.success?).to be false
        expect(mediator.errors).to include('Database error: Database connection failed')
      end

      it 'handles StandardError' do
        error = StandardError.new('Unexpected error occurred')
        expect(mock_where_clause).to receive(:delete).and_raise(error)

        mediator = described_class.new(slug)
        mediator.call

        expect(mediator.success?).to be false
        expect(mediator.errors).to include('Unexpected error: Unexpected error occurred')
      end

      it 'does not set deleted_dataclip when error occurs' do
        error = StandardError.new('Unexpected error occurred')
        expect(mock_where_clause).to receive(:delete).and_raise(error)

        mediator = described_class.new(slug)
        mediator.call

        expect(mediator.deleted_dataclip).to be_nil
      end
    end
  end

  describe 'cache invalidation' do
    before do
      allow(mock_table).to receive(:where).with(slug: slug).and_return(mock_table)
      allow(mock_table).to receive(:first).and_return(existing_dataclip)
      allow(mock_table).to receive(:delete).and_return(1)
    end

    it 'invalidates cache when dataclip is deleted' do
      expect(ClipWorker).to receive(:invalidate_cache).with(slug)

      mediator = described_class.new(slug)
      mediator.call

      expect(mediator.success?).to be true
      expect(mediator.deleted_dataclip).to eq(existing_dataclip)
    end

    it 'handles cache invalidation errors gracefully' do
      allow(ClipWorker).to receive(:invalidate_cache).and_raise(StandardError.new('Cache error'))

      # Capture stdout to verify warning is logged
      original_stdout = $stdout
      $stdout = StringIO.new

      begin
        mediator = described_class.new(slug)
        mediator.call

        # Delete should still succeed despite cache error
        expect(mediator.success?).to be true
        expect(mediator.deleted_dataclip).to eq(existing_dataclip)

        # Warning should be logged (except in test environment)
        if ENV['RACK_ENV'] != 'test'
          output = $stdout.string
          expect(output).to include('Warning: Failed to invalidate cache')
        end
      ensure
        $stdout = original_stdout
      end
    end

    context 'when ClipWorker is not defined' do
      it 'handles missing ClipWorker gracefully' do
        hide_const('ClipWorker')

        mediator = described_class.new(slug)
        mediator.call

        # Delete should still succeed
        expect(mediator.success?).to be true
        expect(mediator.deleted_dataclip).to eq(existing_dataclip)
      end
    end
  end
end
