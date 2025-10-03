# frozen_string_literal: true

require 'sequel'
require 'json'

# SQLite database initializer for caching
module SQLiteInitializer
  class << self
    def setup!
      establish_connection
      create_tables
      setup_helper_methods
      puts '✓ SQLite cache database initialized'
    end

    private

    def establish_connection
      # Create in-memory SQLite database for caching
      cache_connection = Sequel.sqlite # In-memory database

      Object.const_set(:CACHE_DB, cache_connection)
      puts '  - SQLite Cache: In-memory database'
    end

    def create_tables
      create_cache_table
    end

    def create_cache_table
      return if CACHE_DB.table_exists?(:query_results)

      CACHE_DB.create_table :query_results do
        String :cache_key, primary_key: true
        Text :result_data
        DateTime :cached_at, default: Sequel::CURRENT_TIMESTAMP
        Integer :ttl_seconds, default: 3600 # 1 hour default TTL
      end
      puts '  - Created query_results cache table'
    end

    def setup_helper_methods
      Object.class_eval do
        # Cache query results in SQLite
        def cache_query_result(cache_key, result_data, ttl_seconds = 3600)
          CACHE_DB[:query_results].insert_conflict(:replace).insert(
            cache_key: cache_key,
            result_data: result_data.to_json,
            cached_at: Time.now,
            ttl_seconds: ttl_seconds
          )
        end

        # Get cached result from SQLite
        def get_cached_result(cache_key)
          cached = CACHE_DB[:query_results].where(cache_key: cache_key).first
          return nil unless cached

          # Check if cache is expired
          if Time.now > (cached[:cached_at] + cached[:ttl_seconds])
            CACHE_DB[:query_results].where(cache_key: cache_key).delete
            return nil
          end

          JSON.parse(cached[:result_data])
        end

        # Clear expired cache entries
        def clear_expired_cache
          CACHE_DB[:query_results].where(
            Sequel.lit('datetime(cached_at, "+" || ttl_seconds || " seconds") < datetime("now")')
          ).delete
        end

        # Clear all cache entries
        def clear_all_cache
          CACHE_DB[:query_results].delete
        end
      end

      puts '  - SQLite cache helper methods loaded'
    end

    # Alternative file-based cache setup (if needed)
    def self.setup_file_cache!(cache_file = 'tmp/cache.db')
      file_connection = Sequel.sqlite(cache_file)
      Object.const_set(:CACHE_DB, file_connection)
    end
  end
end
