# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../config/initializers/sqlite'

RSpec.describe SQLiteInitializer do
  before(:all) do
    # Setup SQLite cache for testing
    SQLiteInitializer.setup!
  end

  after(:each) do
    # Clean up cache between tests
    CACHE_DB[:dataclip_results].delete if defined?(CACHE_DB)
    CACHE_DB[:schema_cache].delete if defined?(CACHE_DB)
    CACHE_DB[:cache_stats].delete if defined?(CACHE_DB)
  end

  describe '.setup!' do
    it 'creates the CACHE_DB constant' do
      expect(defined?(CACHE_DB)).to be_truthy
      expect(CACHE_DB).to be_a(Sequel::Database)
    end

    it 'creates required tables' do
      expect(CACHE_DB.table_exists?(:dataclip_results)).to be true
      expect(CACHE_DB.table_exists?(:schema_cache)).to be true
      expect(CACHE_DB.table_exists?(:cache_stats)).to be true
    end

    it 'creates indexes for performance' do
      indexes = CACHE_DB.indexes(:dataclip_results)
      expect(indexes).not_to be_empty

      schema_indexes = CACHE_DB.indexes(:schema_cache)
      expect(schema_indexes).not_to be_empty
    end
  end

  describe 'dataclip cache helper methods' do
    let(:sql_query) { 'SELECT 1 as test' }
    let(:result_hash) do
      {
        success: true,
        data: [{ test: 1 }],
        columns: ['test'],
        row_count: 1,
        execution_time: 10.5,
        errors: []
      }
    end

    describe '#generate_dataclip_cache_key' do
      it 'generates consistent cache keys for same query' do
        key1 = generate_dataclip_cache_key(sql_query)
        key2 = generate_dataclip_cache_key(sql_query)
        expect(key1).to eq(key2)
      end

      it 'generates different keys for different queries' do
        key1 = generate_dataclip_cache_key('SELECT 1')
        key2 = generate_dataclip_cache_key('SELECT 2')
        expect(key1).not_to eq(key2)
      end

      it 'includes dataclip slug when provided' do
        key_with_slug = generate_dataclip_cache_key(sql_query, nil, 'test-slug')
        key_without_slug = generate_dataclip_cache_key(sql_query)
        expect(key_with_slug).not_to eq(key_without_slug)
        expect(key_with_slug).to include('test-slug')
      end

      it 'includes parameters hash when provided' do
        params = { user_id: 123 }
        key_with_params = generate_dataclip_cache_key(sql_query, params)
        key_without_params = generate_dataclip_cache_key(sql_query)
        expect(key_with_params).not_to eq(key_without_params)
      end
    end

    describe '#cache_dataclip_result' do
      it 'stores result in cache' do
        cache_key = cache_dataclip_result(sql_query, result_hash)
        expect(cache_key).to be_a(String)

        cached_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first
        expect(cached_entry).not_to be_nil
        expect(cached_entry[:sql_query]).to eq(sql_query)
      end

      it 'separates result data from metadata' do
        cache_key = cache_dataclip_result(sql_query, result_hash)
        cached_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first

        result_data = JSON.parse(cached_entry[:result_data], symbolize_names: true)
        result_metadata = JSON.parse(cached_entry[:result_metadata], symbolize_names: true)

        expect(result_data).to have_key(:success)
        expect(result_data).to have_key(:data)
        expect(result_metadata).to have_key(:columns)
        expect(result_metadata).to have_key(:row_count)
      end

      it 'sets expiration timestamp' do
        ttl = 1800 # 30 minutes
        cache_key = cache_dataclip_result(sql_query, result_hash, nil, nil, ttl)
        cached_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first

        expect(cached_entry[:expires_at]).to be > Time.now
        expect(cached_entry[:expires_at]).to be < (Time.now + ttl + 10) # Allow for small timing differences
        expect(cached_entry[:ttl_seconds]).to eq(ttl)
      end
    end

    describe '#get_cached_dataclip_result' do
      before do
        cache_dataclip_result(sql_query, result_hash)
      end

      it 'retrieves cached result' do
        cached_result = get_cached_dataclip_result(sql_query)
        expect(cached_result).not_to be_nil
        expect(cached_result[:success]).to be true
        expect(cached_result[:data]).to eq(result_hash[:data])
        expect(cached_result[:columns]).to eq(result_hash[:columns])
      end

      it 'includes cache metadata in result' do
        cached_result = get_cached_dataclip_result(sql_query)
        expect(cached_result[:cached]).to be true
        expect(cached_result[:cache_key]).to be_a(String)
        expect(cached_result[:cached_at]).to be_a(Time)
      end

      it 'increments hit count on access' do
        cache_key = generate_dataclip_cache_key(sql_query)
        initial_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first
        expect(initial_entry[:hit_count]).to eq(0)

        get_cached_dataclip_result(sql_query)

        updated_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first
        expect(updated_entry[:hit_count]).to eq(1)
      end

      it 'returns nil for expired entries' do
        # Create an expired entry
        cache_key = cache_dataclip_result(sql_query, result_hash, nil, nil, -1) # Already expired

        cached_result = get_cached_dataclip_result(sql_query)
        expect(cached_result).to be_nil

        # Verify expired entry was deleted
        cached_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first
        expect(cached_entry).to be_nil
      end
    end

    describe '#invalidate_dataclip_cache' do
      before do
        cache_dataclip_result(sql_query, result_hash, 'test-slug')
        cache_dataclip_result('SELECT 2', result_hash, 'test-slug')
        cache_dataclip_result('SELECT 3', result_hash, 'other-slug')
      end

      it 'removes cache entries for specific dataclip slug' do
        deleted_count = invalidate_dataclip_cache('test-slug')
        expect(deleted_count).to eq(2)

        # Verify only the correct entries were deleted
        remaining_entries = CACHE_DB[:dataclip_results].where(dataclip_slug: 'test-slug').count
        expect(remaining_entries).to eq(0)

        other_entries = CACHE_DB[:dataclip_results].where(dataclip_slug: 'other-slug').count
        expect(other_entries).to eq(1)
      end
    end

    describe '#get_dataclip_cache_stats' do
      before do
        # Create some test cache entries with different hit counts
        cache_dataclip_result('SELECT 1', result_hash)
        cache_dataclip_result('SELECT 2', result_hash)

        # Simulate some hits
        get_cached_dataclip_result('SELECT 1')
        get_cached_dataclip_result('SELECT 1')
        get_cached_dataclip_result('SELECT 2')
      end

      it 'returns comprehensive cache statistics' do
        stats = get_dataclip_cache_stats

        expect(stats).to have_key(:total_entries)
        expect(stats).to have_key(:active_entries)
        expect(stats).to have_key(:expired_entries)
        expect(stats).to have_key(:total_hits)
        expect(stats).to have_key(:avg_hits_per_entry)
        expect(stats).to have_key(:total_data_size_bytes)
        expect(stats).to have_key(:cache_hit_ratio)

        expect(stats[:total_entries]).to eq(2)
        expect(stats[:total_hits]).to eq(3)
      end
    end
  end

  describe 'schema cache helper methods' do
    let(:connection_url) { 'postgres://user:pass@localhost:5432/testdb' }
    let(:schema_result) do
      {
        success: true,
        schema: {
          'users' => {
            columns: [
              { name: 'id', type: 'integer', nullable: false, primary_key: true },
              { name: 'name', type: 'varchar(255)', nullable: false, primary_key: false }
            ],
            column_count: 2
          }
        },
        errors: []
      }
    end

    describe '#generate_schema_cache_key' do
      it 'generates consistent cache keys for same connection' do
        key1 = generate_schema_cache_key(connection_url)
        key2 = generate_schema_cache_key(connection_url)
        expect(key1).to eq(key2)
      end

      it 'generates different keys for different connections' do
        key1 = generate_schema_cache_key('postgres://localhost:5432/db1')
        key2 = generate_schema_cache_key('postgres://localhost:5432/db2')
        expect(key1).not_to eq(key2)
      end

      it 'starts with schema prefix' do
        key = generate_schema_cache_key(connection_url)
        expect(key).to start_with('schema:')
      end
    end

    describe '#cache_schema_result' do
      it 'stores schema result in cache' do
        cache_key = cache_schema_result(connection_url, schema_result)
        expect(cache_key).to be_a(String)

        cached_entry = CACHE_DB[:schema_cache].where(cache_key: cache_key).first
        expect(cached_entry).not_to be_nil
      end

      it 'calculates schema metadata' do
        cache_key = cache_schema_result(connection_url, schema_result)
        cached_entry = CACHE_DB[:schema_cache].where(cache_key: cache_key).first

        metadata = JSON.parse(cached_entry[:schema_metadata], symbolize_names: true)
        expect(metadata[:table_count]).to eq(1)
        expect(metadata[:total_columns]).to eq(2)
      end

      it 'uses longer default TTL for schemas' do
        cache_key = cache_schema_result(connection_url, schema_result)
        cached_entry = CACHE_DB[:schema_cache].where(cache_key: cache_key).first

        expect(cached_entry[:ttl_seconds]).to eq(7200) # 2 hours default
      end
    end

    describe '#get_cached_schema_result' do
      before do
        cache_schema_result(connection_url, schema_result)
      end

      it 'retrieves cached schema result' do
        cached_result = get_cached_schema_result(connection_url)
        expect(cached_result).not_to be_nil
        expect(cached_result[:success]).to be true
        expect(cached_result[:schema]).to eq(schema_result[:schema])
      end

      it 'includes cache and metadata information' do
        cached_result = get_cached_schema_result(connection_url)
        expect(cached_result[:cached]).to be true
        expect(cached_result[:table_count]).to eq(1)
        expect(cached_result[:total_columns]).to eq(2)
      end
    end

    describe '#get_schema_cache_stats' do
      before do
        cache_schema_result(connection_url, schema_result)
        get_cached_schema_result(connection_url)
      end

      it 'returns schema-specific cache statistics' do
        stats = get_schema_cache_stats

        expect(stats).to have_key(:total_entries)
        expect(stats).to have_key(:total_hits)
        expect(stats).to have_key(:cache_hit_ratio)

        expect(stats[:total_entries]).to eq(1)
        expect(stats[:total_hits]).to eq(1)
      end
    end
  end

  describe 'cache configuration' do
    describe '.cache_config' do
      it 'returns configuration hash' do
        config = SQLiteInitializer.cache_config
        expect(config).to be_a(Hash)
        expect(config).to have_key(:enabled)
        expect(config).to have_key(:default_ttl)
        expect(config).to have_key(:schema_enabled)
        expect(config).to have_key(:schema_default_ttl)
      end
    end

    describe '.caching_enabled?' do
      it 'returns boolean based on configuration' do
        result = SQLiteInitializer.caching_enabled?
        expect([true, false]).to include(result)
      end
    end

    describe '.schema_caching_enabled?' do
      it 'returns boolean based on schema configuration' do
        result = SQLiteInitializer.schema_caching_enabled?
        expect([true, false]).to include(result)
      end
    end
  end
end
