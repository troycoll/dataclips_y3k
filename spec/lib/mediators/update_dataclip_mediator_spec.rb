# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/mediators/update_dataclip_mediator'

RSpec.describe UpdateDataclipMediator do
  let(:slug) { 'test-dataclip-123' }
  let(:valid_params) do
    {
      title: 'Updated Dataclip',
      description: 'An updated test dataclip',
      sql_query: 'SELECT * FROM updated_users',
      created_by: 'updated_user'
    }
  end

  let(:existing_dataclip) do
    {
      slug: slug,
      title: 'Original Dataclip',
      description: 'Original description',
      sql_query: 'SELECT * FROM users',
      created_by: 'original_user',
      created_at: Time.now - 3600,
      updated_at: Time.now - 3600
    }
  end

  let(:mock_table) { double('dataclips_table') }

  before do
    allow(DB).to receive(:[]).with(:dataclips).and_return(mock_table)
  end

  include_examples 'a mediator class method', UpdateDataclipMediator, 'test-slug', { title: 'Updated' }

  describe '#initialize' do
    it 'initializes with slug and params' do
      mediator = described_class.new(slug, valid_params)
      expect(mediator.send(:slug)).to eq(slug)
      expect(mediator.send(:title)).to eq('Updated Dataclip')
      expect(mediator.send(:description)).to eq('An updated test dataclip')
      expect(mediator.send(:sql_query)).to eq('SELECT * FROM updated_users')
      expect(mediator.send(:created_by)).to eq('updated_user')
    end

    it 'strips whitespace from string fields' do
      params = {
        title: '  Updated Dataclip  ',
        description: '  An updated test dataclip  ',
        sql_query: '  SELECT * FROM updated_users  ',
        created_by: '  updated_user  '
      }
      mediator = described_class.new(slug, params)
      expect(mediator.send(:title)).to eq('Updated Dataclip')
      expect(mediator.send(:description)).to eq('An updated test dataclip')
      expect(mediator.send(:sql_query)).to eq('SELECT * FROM updated_users')
      expect(mediator.send(:created_by)).to eq('updated_user')
    end

    it 'handles nil values gracefully' do
      params = { title: nil, sql_query: nil }
      mediator = described_class.new(slug, params)
      expect(mediator.send(:title)).to be_nil
      expect(mediator.send(:sql_query)).to be_nil
    end
  end

  describe '#call' do
    context 'with valid params and existing dataclip' do
      before do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: existing_dataclip))
      end

      it 'returns self' do
        allow_any_instance_of(described_class).to receive(:update_dataclip_record)
        mediator = described_class.new(slug, valid_params)
        result = mediator.call
        expect(result).to eq(mediator)
      end

      it 'is successful' do
        allow_any_instance_of(described_class).to receive(:update_dataclip_record)
        mediator = described_class.new(slug, valid_params)
        mediator.call
        expect(mediator.success?).to be true
      end

      it 'calls update_dataclip_record' do
        mediator = described_class.new(slug, valid_params)
        expect(mediator).to receive(:update_dataclip_record)
        mediator.call
      end
    end

    context 'with non-existent dataclip' do
      before do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: nil))
      end

      it 'does not call update_dataclip_record when dataclip does not exist' do
        mediator = described_class.new(slug, valid_params)
        expect(mediator).not_to receive(:update_dataclip_record)
        mediator.call
      end

      it 'is not successful when dataclip does not exist' do
        mediator = described_class.new(slug, valid_params)
        mediator.call
        expect(mediator.success?).to be false
        expect(mediator.errors).to include('Dataclip not found')
      end
    end

    context 'with invalid params' do
      before do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: existing_dataclip))
      end

      it 'does not call update_dataclip_record when validation fails' do
        long_title = 'a' * 256
        mediator = described_class.new(slug, { title: long_title })
        expect(mediator).not_to receive(:update_dataclip_record)
        mediator.call
      end

      it 'is not successful when validation fails' do
        long_title = 'a' * 256
        mediator = described_class.new(slug, { title: long_title })
        mediator.call
        expect(mediator.success?).to be false
      end
    end
  end

  describe '#dataclip' do
    it 'exposes the dataclip attribute' do
      mediator = described_class.new(slug, valid_params)
      expect(mediator).to respond_to(:dataclip)
    end
  end

  describe 'validation' do
    before do
      allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: existing_dataclip))
    end

    describe 'title validation' do
      it 'does not require title when not provided' do
        allow_any_instance_of(described_class).to receive(:update_dataclip_record)
        mediator = described_class.new(slug, { sql_query: 'SELECT 1' })
        mediator.call
        expect(mediator.success?).to be true
      end

      it 'requires title to be present when provided but empty' do
        mediator = described_class.new(slug, { title: '' })
        mediator.call
        expect(mediator.errors).to include('Title is required')
      end

      it 'requires title to be 255 characters or less when provided' do
        long_title = 'a' * 256
        mediator = described_class.new(slug, { title: long_title })
        mediator.call
        expect(mediator.errors).to include('Title must be 255 characters or less')
      end

      it 'allows title of exactly 255 characters' do
        title_255 = 'a' * 255
        allow_any_instance_of(described_class).to receive(:update_dataclip_record)
        mediator = described_class.new(slug, { title: title_255 })
        mediator.call
        expect(mediator.errors).not_to include('Title must be 255 characters or less')
      end
    end

    describe 'sql_query validation' do
      it 'does not require sql_query when not provided' do
        allow_any_instance_of(described_class).to receive(:update_dataclip_record)
        mediator = described_class.new(slug, { title: 'Updated' })
        mediator.call
        expect(mediator.success?).to be true
      end

      it 'requires sql_query to be present when provided but empty' do
        mediator = described_class.new(slug, { sql_query: '' })
        mediator.call
        expect(mediator.errors).to include('SQL query is required')
      end

      it 'requires sql_query to be 10,000 characters or less when provided' do
        long_query = 'a' * 10_001
        mediator = described_class.new(slug, { sql_query: long_query })
        mediator.call
        expect(mediator.errors).to include('SQL query must be 10,000 characters or less')
      end

      it 'allows sql_query of exactly 10,000 characters' do
        query_10000 = 'a' * 10_000
        allow_any_instance_of(described_class).to receive(:update_dataclip_record)
        mediator = described_class.new(slug, { sql_query: query_10000 })
        mediator.call
        expect(mediator.errors).not_to include('SQL query must be 10,000 characters or less')
      end
    end

    describe 'dataclip existence validation' do
      it 'adds error when dataclip does not exist' do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: nil))
        mediator = described_class.new(slug, valid_params)
        mediator.call
        expect(mediator.errors).to include('Dataclip not found')
      end
    end
  end

  describe 'database operations' do
    before do
      allow(mock_table).to receive(:where).with(slug: slug).and_return(double(first: existing_dataclip))
    end

    describe '#update_dataclip_record' do
      let(:mock_where_clause) { double('where_clause') }

      before do
        allow(mock_table).to receive(:where).with(slug: slug).and_return(mock_where_clause)
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip)
      end

      it 'updates record with all provided fields' do
        expected_updates = {
          updated_at: anything,
          title: 'Updated Dataclip',
          description: 'An updated test dataclip',
          sql_query: 'SELECT * FROM updated_users',
          created_by: 'updated_user'
        }

        expect(mock_where_clause).to receive(:update).with(expected_updates)
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip.merge(expected_updates))

        mediator = described_class.new(slug, valid_params)
        mediator.call
      end

      it 'updates only provided fields' do
        partial_params = { title: 'Updated Title Only' }
        expected_updates = {
          updated_at: anything,
          title: 'Updated Title Only'
        }

        expect(mock_where_clause).to receive(:update).with(expected_updates)
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip.merge(expected_updates))

        mediator = described_class.new(slug, partial_params)
        mediator.call
      end

      it 'sets description to nil when empty string provided' do
        params = { description: '' }
        expected_updates = {
          updated_at: anything,
          description: nil
        }

        expect(mock_where_clause).to receive(:update).with(expected_updates)
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip.merge(expected_updates))

        mediator = described_class.new(slug, params)
        mediator.call
      end

      it 'sets created_by to nil when empty string provided' do
        params = { created_by: '' }
        expected_updates = {
          updated_at: anything,
          created_by: nil
        }

        expect(mock_where_clause).to receive(:update).with(expected_updates)
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip.merge(expected_updates))

        mediator = described_class.new(slug, params)
        mediator.call
      end

      it 'does not update fields that are not provided' do
        params = { title: 'Updated Title' }

        expect(mock_where_clause).to receive(:update) do |updates|
          expect(updates).not_to have_key(:description)
          expect(updates).not_to have_key(:sql_query)
          expect(updates).not_to have_key(:created_by)
        end
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip)

        mediator = described_class.new(slug, params)
        mediator.call
      end

      it 'always includes updated_at timestamp' do
        expect(mock_where_clause).to receive(:update) do |updates|
          expect(updates).to have_key(:updated_at)
          expect(updates[:updated_at]).to be_a(Time)
        end
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip)

        mediator = described_class.new(slug, { title: 'Updated' })
        mediator.call
      end
    end

  describe 'database error handling' do
    include_examples 'a mediator with database error handling', UpdateDataclipMediator, :update_dataclip_record, 'test-slug', { title: 'Updated' } do
      def setup_error_scenario(error)
        allow(mock_table).to receive(:where).with(slug: 'test-slug').and_return(double(first: existing_dataclip))
        mock_where_clause = double('where_clause')
        allow(mock_table).to receive(:where).with(slug: 'test-slug').and_return(mock_where_clause)
        allow(mock_where_clause).to receive(:first).and_return(existing_dataclip)
        allow(mock_where_clause).to receive(:update).and_raise(error)
      end
    end
  end
  end
end
