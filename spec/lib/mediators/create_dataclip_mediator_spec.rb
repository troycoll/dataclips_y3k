# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/mediators/create_dataclip_mediator'

RSpec.describe CreateDataclipMediator do
  let(:valid_params) do
    {
      title: 'Test Dataclip',
      description: 'A test dataclip',
      sql_query: 'SELECT * FROM users',
      created_by: 'test_user',
      addon_id: 'test_addon_id',
      addon_name: 'test_addon_name'
    }
  end

  let(:minimal_params) do
    {
      title: 'Test Dataclip',
      sql_query: 'SELECT * FROM users'
    }
  end

  before do
    # Mock the database connection and table
    allow(DB).to receive(:[]).with(:dataclips).and_return(double('dataclips_table'))
  end

  include_examples 'a mediator class method', CreateDataclipMediator, { title: 'Test', sql_query: 'SELECT 1' }

  describe '#initialize' do
    it 'initializes with provided params' do
      mediator = described_class.new(valid_params)
      expect(mediator.send(:title)).to eq('Test Dataclip')
      expect(mediator.send(:description)).to eq('A test dataclip')
      expect(mediator.send(:sql_query)).to eq('SELECT * FROM users')
      expect(mediator.send(:created_by)).to eq('test_user')
    end

    it 'strips whitespace from string fields' do
      params = {
        title: '  Test Dataclip  ',
        description: '  A test dataclip  ',
        sql_query: '  SELECT * FROM users  ',
        created_by: '  test_user  '
      }
      mediator = described_class.new(params)
      expect(mediator.send(:title)).to eq('Test Dataclip')
      expect(mediator.send(:description)).to eq('A test dataclip')
      expect(mediator.send(:sql_query)).to eq('SELECT * FROM users')
      expect(mediator.send(:created_by)).to eq('test_user')
    end

    it 'generates a slug automatically' do
      mediator = described_class.new(valid_params)
      slug = mediator.send(:slug)
      expect(slug).to match(/\A[a-z0-9]{16}\z/)
    end

    it 'handles nil values gracefully' do
      params = { title: nil, sql_query: nil }
      mediator = described_class.new(params)
      expect(mediator.send(:title)).to be_nil
      expect(mediator.send(:sql_query)).to be_nil
    end
  end

  describe '#call' do
    context 'with valid params' do
      it 'returns self' do
        allow_any_instance_of(described_class).to receive(:create_dataclip_record)
        mediator = described_class.new(valid_params)
        result = mediator.call
        expect(result).to eq(mediator)
      end

      it 'is successful' do
        allow_any_instance_of(described_class).to receive(:create_dataclip_record)
        mediator = described_class.new(valid_params)
        mediator.call
        expect(mediator.success?).to be true
      end

      it 'calls create_dataclip_record' do
        mediator = described_class.new(valid_params)
        expect(mediator).to receive(:create_dataclip_record)
        mediator.call
      end
    end

    context 'with invalid params' do
      it 'does not call create_dataclip_record when validation fails' do
        mediator = described_class.new({ title: '', sql_query: '' })
        expect(mediator).not_to receive(:create_dataclip_record)
        mediator.call
      end

      it 'is not successful when validation fails' do
        mediator = described_class.new({ title: '', sql_query: '' })
        mediator.call
        expect(mediator.success?).to be false
      end
    end
  end

  describe '#dataclip' do
    it 'exposes the dataclip attribute' do
      mediator = described_class.new(valid_params)
      expect(mediator).to respond_to(:dataclip)
    end
  end

  describe 'validation' do
    describe 'title validation' do
      it 'requires title to be present' do
        mediator = described_class.new(valid_params.merge(title: ''))
        mediator.call
        expect(mediator.errors).to include('Title is required')
      end

      it 'requires title to be 255 characters or less' do
        long_title = 'a' * 256
        mediator = described_class.new(valid_params.merge(title: long_title))
        mediator.call
        expect(mediator.errors).to include('Title must be 255 characters or less')
      end

      it 'allows title of exactly 255 characters' do
        title_255 = 'a' * 255
        allow_any_instance_of(described_class).to receive(:create_dataclip_record)
        mediator = described_class.new(valid_params.merge(title: title_255))
        mediator.call
        expect(mediator.errors).not_to include('Title must be 255 characters or less')
      end
    end

    describe 'sql_query validation' do
      it 'requires sql_query to be present' do
        mediator = described_class.new(valid_params.merge(sql_query: ''))
        mediator.call
        expect(mediator.errors).to include('SQL query is required')
      end

      it 'requires sql_query to be 10,000 characters or less' do
        long_query = 'SELECT * FROM users WHERE id = 1 AND ' + ('condition = true AND ' * 500)
        mediator = described_class.new(valid_params.merge(sql_query: long_query))
        mediator.call
        expect(mediator.errors).to include('SQL query must be 10,000 characters or less')
      end

      it 'allows sql_query of exactly 10,000 characters' do
        query_10000 = 'a' * 10_000
        allow_any_instance_of(described_class).to receive(:create_dataclip_record)
        mediator = described_class.new(valid_params.merge(sql_query: query_10000))
        mediator.call
        expect(mediator.errors).not_to include('SQL query must be 10,000 characters or less')
      end
    end

    describe 'optional fields' do
      it 'does not require description' do
        allow_any_instance_of(described_class).to receive(:create_dataclip_record)
        mediator = described_class.new(minimal_params)
        mediator.call
        expect(mediator.success?).to be true
      end

      it 'does not require created_by' do
        allow_any_instance_of(described_class).to receive(:create_dataclip_record)
        mediator = described_class.new(minimal_params)
        mediator.call
        expect(mediator.success?).to be true
      end
    end
  end

  describe 'database operations' do
    let(:mock_table) { double('dataclips_table') }

    before do
      allow(DB).to receive(:[]).with(:dataclips).and_return(mock_table)
    end

    describe '#create_dataclip_record' do
      it 'inserts a record with all fields' do
        expected_data = {
          slug: anything,
          title: 'Test Dataclip',
          description: 'A test dataclip',
          sql_query: 'SELECT * FROM users',
          addon_id: 'test_addon_id',
          addon_name: 'test_addon_name',
          created_by: 'test_user',
          created_at: anything,
          updated_at: anything
        }

        expect(mock_table).to receive(:insert).with(expected_data).and_return(1)

        mediator = described_class.new(valid_params)
        mediator.call
      end

      it 'inserts a record with minimal fields' do
        expected_data = {
          slug: anything,
          title: 'Test Dataclip',
          description: nil,
          sql_query: 'SELECT * FROM users',
          addon_id: nil,
          addon_name: nil,
          created_by: nil,
          created_at: anything,
          updated_at: anything
        }

        expect(mock_table).to receive(:insert).with(expected_data).and_return(1)

        mediator = described_class.new(minimal_params)
        mediator.call
      end

      it 'sets description to nil when empty' do
        params = valid_params.merge(description: '')
        expected_data = hash_including(description: nil)

        expect(mock_table).to receive(:insert).with(expected_data).and_return(1)

        mediator = described_class.new(params)
        mediator.call
      end

      it 'sets created_by to nil when empty' do
        params = valid_params.merge(created_by: '')
        expected_data = hash_including(created_by: nil)

        expect(mock_table).to receive(:insert).with(expected_data).and_return(1)

        mediator = described_class.new(params)
        mediator.call
      end
    end

  describe 'database error handling' do
    include_examples 'a mediator with database error handling', CreateDataclipMediator, :create_dataclip_record, { title: 'Test', sql_query: 'SELECT 1' } do
      def setup_error_scenario(error)
        allow(mock_table).to receive(:insert).and_raise(error)
      end
    end
  end
  end
end
