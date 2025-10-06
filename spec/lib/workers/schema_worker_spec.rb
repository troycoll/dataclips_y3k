# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/workers/schema_worker'

RSpec.describe SchemaWorker do
  before(:all) do
    # Ensure we have a test database connection and cache setup (only once)
    Config.setup! if defined?(Config)
    SQLiteInitializer.setup! if defined?(SQLiteInitializer)
  end

  after(:each) do
    # Clean up cache between tests using the centralized reset method
    SQLiteInitializer.reset_cache! if defined?(SQLiteInitializer)
  end

  describe '.fetch_schema' do
    context 'with valid database connection' do
      it 'fetches schema successfully' do
        result = SchemaWorker.fetch_schema

        expect(result[:success]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:schema]).to be_a(Hash)
        expect(result[:fetch_time]).to be > 0
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

    context 'with caching enabled' do
      before do
        allow(SchemaWorker).to receive(:schema_caching_enabled?).and_return(true)
      end

      it 'caches successful schema fetch results' do
        connection_url = ENV['DATABASE_URL']

        # First fetch should hit database and cache result
        result1 = SchemaWorker.fetch_schema(connection_url, cache_enabled: true)
        expect(result1[:success]).to be true
        expect(result1[:cached]).to be_falsy
        expect(result1[:fetch_time]).to be > 0

        # Second fetch should hit cache
        result2 = SchemaWorker.fetch_schema(connection_url, cache_enabled: true)
        expect(result2[:success]).to be true
        expect(result2[:cached]).to be true
        expect(result2[:schema]).to eq(result1[:schema])
      end

      it 'respects cache_enabled parameter' do
        connection_url = ENV['DATABASE_URL']

        # Fetch with caching disabled
        result1 = SchemaWorker.fetch_schema(connection_url, cache_enabled: false)
        expect(result1[:cached]).to be_falsy

        # Fetch again with caching disabled - should not use cache
        result2 = SchemaWorker.fetch_schema(connection_url, cache_enabled: false)
        expect(result2[:cached]).to be_falsy
      end

      it 'uses custom cache TTL when provided' do
        connection_url = ENV['DATABASE_URL']
        custom_ttl = 3600 # 1 hour

        SchemaWorker.fetch_schema(connection_url, cache_enabled: true, cache_ttl: custom_ttl)

        # Verify the cached entry has the custom TTL
        cache_key = SchemaCache.send(:generate_cache_key, connection_url)
        cached_entry = CACHE_DB[:schema_cache].where(cache_key: cache_key).first
        expect(cached_entry[:ttl_seconds]).to eq(custom_ttl)
      end

      it 'does not cache failed schema fetches' do
        invalid_url = 'invalid://connection/url'

        result = SchemaWorker.fetch_schema(invalid_url, cache_enabled: true)
        expect(result[:success]).to be false

        # Verify no cache entry was created
        cache_key = SchemaCache.send(:generate_cache_key, invalid_url)
        cached_entry = CACHE_DB[:schema_cache].where(cache_key: cache_key).first
        expect(cached_entry).to be_nil
      end

      it 'includes metadata in cached results' do
        connection_url = ENV['DATABASE_URL']

        # Cache the result
        SchemaWorker.fetch_schema(connection_url, cache_enabled: true)

        # Retrieve from cache
        cached_result = SchemaWorker.fetch_schema(connection_url, cache_enabled: true)
        expect(cached_result[:cached]).to be true
        expect(cached_result[:table_count]).to be > 0
        expect(cached_result[:total_columns]).to be > 0
      end
    end

    context 'with caching disabled' do
      before do
        allow(SchemaWorker).to receive(:schema_caching_enabled?).and_return(false)
      end

      it 'does not use cache when disabled' do
        connection_url = ENV['DATABASE_URL']

        result1 = SchemaWorker.fetch_schema(connection_url)
        result2 = SchemaWorker.fetch_schema(connection_url)

        expect(result1[:cached]).to be_falsy
        expect(result2[:cached]).to be_falsy
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

  describe 'cache management methods' do
    before do
      allow(SchemaWorker).to receive(:schema_caching_enabled?).and_return(true)
    end

    describe '.clear_cache' do
      before do
        # Create some cached schema entries
        SchemaWorker.fetch_schema(ENV['DATABASE_URL'], cache_enabled: true)
      end

      it 'removes all schema cache entries' do
        # Verify cache entry exists
        cached_entries = CACHE_DB[:schema_cache].count
        expect(cached_entries).to eq(1)

        # Clear cache
        cleared_count = SchemaWorker.clear_cache
        expect(cleared_count).to eq(1)

        # Verify cache entries were removed
        cached_entries = CACHE_DB[:schema_cache].count
        expect(cached_entries).to eq(0)
      end

      it 'returns 0 when caching is disabled' do
        allow(SchemaWorker).to receive(:schema_caching_enabled?).and_return(false)
        result = SchemaWorker.clear_cache
        expect(result).to eq(0)
      end
    end

    describe '.cache_stats' do
      before do
        # Create some cached entries
        SchemaWorker.fetch_schema(ENV['DATABASE_URL'], cache_enabled: true)
        SchemaWorker.fetch_schema(ENV['DATABASE_URL'], cache_enabled: true) # Hit cache
      end

      it 'returns schema cache statistics' do
        stats = SchemaWorker.cache_stats
        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:total_entries)
        expect(stats).to have_key(:total_hits)
        expect(stats).to have_key(:cache_hit_ratio)
        expect(stats[:total_entries]).to eq(1)
        expect(stats[:total_hits]).to eq(1)
      end

      it 'returns empty hash when caching is disabled' do
        allow(SchemaWorker).to receive(:schema_caching_enabled?).and_return(false)
        stats = SchemaWorker.cache_stats
        expect(stats).to eq({})
      end
    end

    describe '.cleanup_cache' do
      it 'removes expired schema cache entries' do
        # Create an expired entry by setting TTL to -1
        SchemaWorker.fetch_schema(ENV['DATABASE_URL'], cache_enabled: true, cache_ttl: -1)

        cleared_count = SchemaWorker.cleanup_cache
        expect(cleared_count).to be >= 0
      end

      it 'returns 0 when caching is disabled' do
        allow(SchemaWorker).to receive(:schema_caching_enabled?).and_return(false)
        result = SchemaWorker.cleanup_cache
        expect(result).to eq(0)
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
    it 'logs schema fetch completion with timing' do
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
        expect(output).to match(/\d+ms/) # Should include timing
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

  describe 'private helper methods' do
    describe '.schema_caching_enabled?' do
      it 'returns false when SQLiteInitializer is not defined' do
        hide_const('SQLiteInitializer')
        expect(SchemaWorker.send(:schema_caching_enabled?)).to be false
      end

      it 'returns configuration value when SQLiteInitializer is available' do
        allow(SQLiteInitializer).to receive(:schema_caching_enabled?).and_return(true)
        expect(SchemaWorker.send(:schema_caching_enabled?)).to be true

        allow(SQLiteInitializer).to receive(:schema_caching_enabled?).and_return(false)
        expect(SchemaWorker.send(:schema_caching_enabled?)).to be false
      end
    end

    describe '.default_schema_cache_ttl' do
      it 'returns default value when SQLiteInitializer is not available' do
        hide_const('SQLiteInitializer')
        expect(SchemaWorker.send(:default_schema_cache_ttl)).to eq(7200)
      end

      it 'returns configured value when available' do
        allow(SQLiteInitializer).to receive(:cache_config).and_return({ schema_default_ttl: 14_400 })
        expect(SchemaWorker.send(:default_schema_cache_ttl)).to eq(14_400)
      end
    end

    describe '.sanitize_connection_for_log' do
      it 'removes password from connection URL' do
        url_with_password = 'postgres://user:secret@localhost:5432/testdb'
        sanitized = SchemaWorker.send(:sanitize_connection_for_log, url_with_password)
        expect(sanitized).not_to include('secret')
        expect(sanitized).to include('***')
      end

      it 'handles URLs without passwords' do
        url_without_password = 'postgres://localhost:5432/testdb'
        sanitized = SchemaWorker.send(:sanitize_connection_for_log, url_without_password)
        expect(sanitized).to include('postgres://localhost:5432/testdb')
      end

      it 'handles invalid URLs gracefully' do
        invalid_url = 'not-a-valid-url'
        sanitized = SchemaWorker.send(:sanitize_connection_for_log, invalid_url)
        expect(sanitized).to eq('database')
      end
    end
  end
end
