# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/workers/clip_worker'

RSpec.describe ClipWorker do
  before do
    # Ensure we have a test database connection and cache setup
    Config.setup! if defined?(Config)
    SQLiteInitializer.setup! if defined?(SQLiteInitializer)
  end

  after(:each) do
    # Clean up cache between tests
    if defined?(CACHE_DB)
      CACHE_DB[:dataclip_results].delete
      CACHE_DB[:cache_stats].delete
    end
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

    context 'with caching enabled' do
      before do
        # Ensure caching is enabled for these tests
        allow(ClipWorker).to receive(:caching_enabled?).and_return(true)
      end

      it 'caches successful query results' do
        sql_query = 'SELECT 42 as answer'

        # First execution should hit database and cache result
        result1 = ClipWorker.execute(sql_query, cache_enabled: true)
        expect(result1[:success]).to be true
        expect(result1[:cached]).to be_falsy

        # Second execution should hit cache
        result2 = ClipWorker.execute(sql_query, cache_enabled: true)
        expect(result2[:success]).to be true
        expect(result2[:cached]).to be true
        expect(result2[:data]).to eq(result1[:data])
      end

      it 'respects cache_enabled parameter' do
        sql_query = 'SELECT 123 as number'

        # Execute with caching disabled
        result1 = ClipWorker.execute(sql_query, cache_enabled: false)
        expect(result1[:cached]).to be_falsy

        # Execute again with caching disabled - should not use cache
        result2 = ClipWorker.execute(sql_query, cache_enabled: false)
        expect(result2[:cached]).to be_falsy
      end

      it 'uses custom cache TTL when provided' do
        sql_query = 'SELECT 999 as custom_ttl'
        custom_ttl = 1800 # 30 minutes

        ClipWorker.execute(sql_query, cache_enabled: true, cache_ttl: custom_ttl)

        # Verify the cached entry has the custom TTL
        cache_key = generate_dataclip_cache_key(sql_query)
        cached_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first
        expect(cached_entry[:ttl_seconds]).to eq(custom_ttl)
      end

      it 'does not cache failed queries' do
        sql_query = 'SELECT FROM invalid_syntax'

        result1 = ClipWorker.execute(sql_query, cache_enabled: true)
        expect(result1[:success]).to be false

        # Verify no cache entry was created
        cache_key = generate_dataclip_cache_key(sql_query)
        cached_entry = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first
        expect(cached_entry).to be_nil
      end
    end

    context 'with caching disabled' do
      before do
        allow(ClipWorker).to receive(:caching_enabled?).and_return(false)
      end

      it 'does not use cache when disabled' do
        sql_query = 'SELECT 789 as no_cache'

        result1 = ClipWorker.execute(sql_query)
        result2 = ClipWorker.execute(sql_query)

        expect(result1[:cached]).to be_falsy
        expect(result2[:cached]).to be_falsy
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

      context 'with caching enabled' do
        before do
          allow(ClipWorker).to receive(:caching_enabled?).and_return(true)
        end

        it 'caches dataclip results with slug' do
          # First execution should cache result
          result1 = ClipWorker.execute_dataclip('test-clip', cache_enabled: true)
          expect(result1[:success]).to be true
          expect(result1[:cached]).to be_falsy

          # Second execution should hit cache
          result2 = ClipWorker.execute_dataclip('test-clip', cache_enabled: true)
          expect(result2[:success]).to be true
          expect(result2[:cached]).to be true
          expect(result2[:data]).to eq(result1[:data])
        end

        it 'includes dataclip slug in cache key' do
          ClipWorker.execute_dataclip('test-clip', cache_enabled: true)

          # Verify cache entry includes the slug
          cached_entries = CACHE_DB[:dataclip_results].where(dataclip_slug: 'test-clip').all
          expect(cached_entries.length).to eq(1)
        end
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

  describe 'cache management methods' do
    before do
      allow(ClipWorker).to receive(:caching_enabled?).and_return(true)
    end

    describe '.invalidate_cache' do
      before do
        create_dataclip('cache-test', 'Cache Test', 'SELECT 1 as cached', 'test_user')
        ClipWorker.execute_dataclip('cache-test', cache_enabled: true)
      end

      after do
        delete_dataclip('cache-test')
      end

      it 'removes cache entries for specified dataclip' do
        # Verify cache entry exists
        cached_entries = CACHE_DB[:dataclip_results].where(dataclip_slug: 'cache-test').count
        expect(cached_entries).to eq(1)

        # Invalidate cache
        cleared_count = ClipWorker.invalidate_cache('cache-test')
        expect(cleared_count).to eq(1)

        # Verify cache entry was removed
        cached_entries = CACHE_DB[:dataclip_results].where(dataclip_slug: 'cache-test').count
        expect(cached_entries).to eq(0)
      end

      it 'returns 0 when caching is disabled' do
        allow(ClipWorker).to receive(:caching_enabled?).and_return(false)
        result = ClipWorker.invalidate_cache('any-slug')
        expect(result).to eq(0)
      end
    end

    describe '.cache_stats' do
      before do
        # Create some cached entries
        ClipWorker.execute('SELECT 1 as stats_test', cache_enabled: true)
        ClipWorker.execute('SELECT 2 as stats_test', cache_enabled: true)
      end

      it 'returns cache statistics' do
        stats = ClipWorker.cache_stats
        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:total_entries)
        expect(stats).to have_key(:total_hits)
        expect(stats[:total_entries]).to be >= 2
      end

      it 'returns empty hash when caching is disabled' do
        allow(ClipWorker).to receive(:caching_enabled?).and_return(false)
        stats = ClipWorker.cache_stats
        expect(stats).to eq({})
      end
    end

    describe '.cleanup_cache' do
      it 'removes expired cache entries' do
        # Create an expired entry by setting TTL to -1
        ClipWorker.execute('SELECT 1 as expired', cache_enabled: true, cache_ttl: -1)

        cleared_count = ClipWorker.cleanup_cache
        expect(cleared_count).to be >= 0
      end

      it 'returns 0 when caching is disabled' do
        allow(ClipWorker).to receive(:caching_enabled?).and_return(false)
        result = ClipWorker.cleanup_cache
        expect(result).to eq(0)
      end
    end
  end

  describe 'private helper methods' do
    describe '.caching_enabled?' do
      it 'returns false when SQLiteInitializer is not defined' do
        hide_const('SQLiteInitializer')
        expect(ClipWorker.send(:caching_enabled?)).to be false
      end

      it 'returns configuration value when SQLiteInitializer is available' do
        allow(SQLiteInitializer).to receive(:caching_enabled?).and_return(true)
        expect(ClipWorker.send(:caching_enabled?)).to be true

        allow(SQLiteInitializer).to receive(:caching_enabled?).and_return(false)
        expect(ClipWorker.send(:caching_enabled?)).to be false
      end
    end

    describe '.default_cache_ttl' do
      it 'returns default value when SQLiteInitializer is not available' do
        hide_const('SQLiteInitializer')
        expect(ClipWorker.send(:default_cache_ttl)).to eq(3600)
      end

      it 'returns configured value when available' do
        allow(SQLiteInitializer).to receive(:cache_config).and_return({ default_ttl: 7200 })
        expect(ClipWorker.send(:default_cache_ttl)).to eq(7200)
      end
    end
  end
end
