# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/workers/schema_worker'

RSpec.describe SchemaWorker do
  before do
    # Ensure we have a test database connection
    Config.setup! if defined?(Config)
  end

  describe '.fetch_schema' do
    context 'with valid database connection' do
      it 'fetches schema successfully' do
        result = SchemaWorker.fetch_schema

        expect(result[:success]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:schema]).to be_a(Hash)
      end

      it 'includes dataclips table in schema' do
        result = SchemaWorker.fetch_schema

        expect(result[:success]).to be true
        expect(result[:schema]).to have_key('dataclips')

        dataclips_schema = result[:schema]['dataclips']
        expect(dataclips_schema).to have_key(:columns)
        expect(dataclips_schema).to have_key(:column_count)
        expect(dataclips_schema[:columns]).to be_an(Array)
        expect(dataclips_schema[:column_count]).to be > 0
      end

      it 'includes column details for each table' do
        result = SchemaWorker.fetch_schema

        expect(result[:success]).to be true

        result[:schema].each do |_table_name, table_info|
          expect(table_info[:columns]).to be_an(Array)

          table_info[:columns].each do |column|
            expect(column).to have_key(:name)
            expect(column).to have_key(:type)
            expect(column).to have_key(:nullable)
            expect(column).to have_key(:primary_key)

            expect(column[:name]).to be_a(String)
            expect(column[:type]).to be_a(String)
            expect([true, false]).to include(column[:nullable])
            expect([true, false]).to include(column[:primary_key])
          end
        end
      end

      it 'excludes system tables' do
        result = SchemaWorker.fetch_schema

        expect(result[:success]).to be true

        # Check that PostgreSQL system tables are not included
        result[:schema].keys.each do |table_name|
          expect(table_name).not_to match(/^pg_/)
          expect(table_name).not_to match(/^sql_/)
        end
      end
    end

    context 'with custom connection URL' do
      it 'uses provided connection URL' do
        # Use the same DATABASE_URL but explicitly pass it
        connection_url = ENV['DATABASE_URL']
        result = SchemaWorker.fetch_schema(connection_url)

        expect(result[:success]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:schema]).to be_a(Hash)
      end
    end

    context 'with invalid inputs' do
      it 'rejects empty connection URL' do
        expect do
          SchemaWorker.fetch_schema('')
        end.to raise_error(ArgumentError, 'Database connection URL is required')
      end

      it 'rejects nil connection URL' do
        expect do
          SchemaWorker.fetch_schema(nil)
        end.to raise_error(ArgumentError, 'Database connection URL is required')
      end
    end

    context 'with database connection errors' do
      it 'handles invalid connection URL gracefully' do
        invalid_url = 'invalid://connection/url'
        result = SchemaWorker.fetch_schema(invalid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
        expect(result[:schema]).to be_empty
      end
    end
  end

  describe 'PostgreSQL table detection' do
    let(:mock_db) { double('database') }

    before do
      allow(Sequel).to receive(:connect).and_return(mock_db)
      allow(mock_db).to receive(:disconnect)
    end

    it 'queries information_schema for user tables' do
      mock_result = [
        { table_name: 'users' },
        { table_name: 'posts' },
        { table_name: 'dataclips' }
      ]

      expect(mock_db).to receive(:fetch).with(anything).and_return(mock_result)
      allow(mock_db).to receive(:schema).and_return([])

      result = SchemaWorker.fetch_schema

      expect(result[:success]).to be true
    end
  end

  describe 'column type formatting' do
    let(:schema_worker) { SchemaWorker }

    it 'formats string types with max_length' do
      column_info = { max_length: 255 }
      result = schema_worker.send(:format_column_type, :string, column_info)
      expect(result).to eq('varchar(255)')
    end

    it 'formats string types without max_length' do
      column_info = {}
      result = schema_worker.send(:format_column_type, :varchar, column_info)
      expect(result).to eq('varchar')
    end

    it 'formats decimal types with precision and scale' do
      column_info = { precision: 10, scale: 2 }
      result = schema_worker.send(:format_column_type, :decimal, column_info)
      expect(result).to eq('decimal(10,2)')
    end

    it 'formats decimal types with precision only' do
      column_info = { precision: 10 }
      result = schema_worker.send(:format_column_type, :numeric, column_info)
      expect(result).to eq('decimal(10)')
    end

    it 'formats common types correctly' do
      test_cases = [
        [:integer, {}, 'integer'],
        [:bigint, {}, 'bigint'],
        [:text, {}, 'text'],
        [:boolean, {}, 'boolean'],
        [:date, {}, 'date'],
        [:datetime, {}, 'timestamp'],
        [:timestamp, {}, 'timestamp'],
        [:uuid, {}, 'uuid'],
        [:json, {}, 'json'],
        [:jsonb, {}, 'jsonb']
      ]

      test_cases.each do |type, column_info, expected|
        result = schema_worker.send(:format_column_type, type, column_info)
        expect(result).to eq(expected), "Expected #{type} to format as #{expected}, got #{result}"
      end
    end
  end

  describe 'error handling and logging' do
    it 'logs schema fetch completion' do
      # Capture stdout to test logging
      original_stdout = $stdout
      $stdout = StringIO.new

      # Set environment to enable logging
      original_env = ENV['RACK_ENV']
      ENV['RACK_ENV'] = 'development'

      begin
        SchemaWorker.fetch_schema
        output = $stdout.string
        expect(output).to include('[SchemaWorker]')
      ensure
        $stdout = original_stdout
        ENV['RACK_ENV'] = original_env
      end
    end

    it 'does not log in test environment' do
      # Ensure we're in test environment
      expect(ENV['RACK_ENV']).to eq('test')

      # Capture stdout
      original_stdout = $stdout
      $stdout = StringIO.new

      begin
        SchemaWorker.fetch_schema
        output = $stdout.string
        expect(output).not_to include('[SchemaWorker]')
      ensure
        $stdout = original_stdout
      end
    end
  end
end
