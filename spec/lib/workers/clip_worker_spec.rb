# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/workers/clip_worker'

RSpec.describe ClipWorker do
  before do
    # Ensure we have a test database connection
    Config.setup! if defined?(Config)
  end

  describe '.execute' do
    context 'with valid SQL query' do
      it 'executes a simple SELECT query successfully' do
        sql_query = 'SELECT 1 as test_column, \'hello\' as message'
        result = ClipWorker.execute(sql_query)

        expect(result[:success]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:data]).to be_an(Array)
        expect(result[:data].length).to eq(1)
        expect(result[:columns]).to include('test_column', 'message')
        expect(result[:row_count]).to eq(1)
        expect(result[:execution_time]).to be > 0
      end

      it 'handles queries that return no rows' do
        sql_query = 'SELECT 1 as test_column WHERE 1 = 0'
        result = ClipWorker.execute(sql_query)

        expect(result[:success]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:data]).to be_empty
        expect(result[:row_count]).to eq(0)
      end
    end

    context 'with invalid inputs' do
      it 'rejects empty SQL query' do
        expect do
          ClipWorker.execute('')
        end.to raise_error(ArgumentError, 'SQL query cannot be empty')
      end

      it 'rejects nil SQL query' do
        expect do
          ClipWorker.execute(nil)
        end.to raise_error(ArgumentError, 'SQL query cannot be empty')
      end

      it 'rejects dangerous SQL operations' do
        dangerous_queries = [
          'DROP TABLE users',
          'DELETE FROM users',
          'INSERT INTO users VALUES (1)',
          'UPDATE users SET name = "test"',
          'SELECT * FROM users; DROP TABLE users'
        ]

        dangerous_queries.each do |query|
          expect do
            ClipWorker.execute(query)
          end.to raise_error(ArgumentError, 'Query contains potentially dangerous SQL operations')
        end
      end
    end

    context 'with database errors' do
      it 'handles invalid SQL gracefully' do
        sql_query = 'SELECT FROM invalid_syntax'
        result = ClipWorker.execute(sql_query)

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
        expect(result[:data]).to be_empty
        expect(result[:row_count]).to eq(0)
      end
    end
  end

  describe '.execute_dataclip' do
    context 'when dataclip exists' do
      before do
        # Create a test dataclip
        create_dataclip('test-clip', 'Test Clip', 'SELECT 1 as test_value', 'test_user')
      end

      after do
        # Clean up test dataclip
        delete_dataclip('test-clip')
      end

      it 'executes the dataclip SQL successfully' do
        result = ClipWorker.execute_dataclip('test-clip')

        expect(result[:success]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:data]).to be_an(Array)
        expect(result[:data].length).to eq(1)
        expect(result[:columns]).to include('test_value')
        expect(result[:row_count]).to eq(1)
      end
    end

    context 'when dataclip does not exist' do
      it 'returns error for non-existent dataclip' do
        result = ClipWorker.execute_dataclip('non-existent-clip')

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Dataclip with slug 'non-existent-clip' not found")
        expect(result[:data]).to be_empty
        expect(result[:row_count]).to eq(0)
      end
    end
  end
end
