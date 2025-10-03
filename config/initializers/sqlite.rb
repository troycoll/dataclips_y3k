# frozen_string_literal: true

require 'sequel'
require 'json'
require 'digest'

# SQLite database initializer for caching dataclip results
module SQLiteInitializer
  class << self
    def setup!
      establish_connection
      create_tables
      setup_helper_methods
      puts '✓ SQLite cache database initialized'
    end

    # Alternative file-based cache setup (if needed)
    def setup_file_cache!(cache_file = 'tmp/cache.db')
      file_connection = Sequel.sqlite(cache_file)
      Object.const_set(:CACHE_DB, file_connection)
    end

    # Configuration for dataclip caching
    def cache_config
      @cache_config ||= {
        enabled: ENV.fetch('DATACLIP_CACHE_ENABLED', 'true') == 'true',
        default_ttl: ENV.fetch('DATACLIP_CACHE_TTL', '3600').to_i, # 1 hour default
        max_entries: ENV.fetch('DATACLIP_CACHE_MAX_ENTRIES', '1000').to_i,
        cleanup_interval: ENV.fetch('DATACLIP_CACHE_CLEANUP_INTERVAL', '300').to_i, # 5 minutes
        stats_enabled: ENV.fetch('DATACLIP_CACHE_STATS_ENABLED', 'true') == 'true',
        # Schema-specific settings
        schema_enabled: ENV.fetch('SCHEMA_CACHE_ENABLED', 'true') == 'true',
        schema_default_ttl: ENV.fetch('SCHEMA_CACHE_TTL', '7200').to_i, # 2 hours default
        schema_max_entries: ENV.fetch('SCHEMA_CACHE_MAX_ENTRIES', '100').to_i
      }
    end

    # Check if caching is enabled
    def caching_enabled?
      cache_config[:enabled]
    end

    # Check if schema caching is enabled
    def schema_caching_enabled?
      cache_config[:schema_enabled]
    end

    private

    def establish_connection
      # Create in-memory SQLite database for caching
      cache_connection = Sequel.sqlite # In-memory database

      Object.const_set(:CACHE_DB, cache_connection)
      puts '  - SQLite Cache: In-memory database'
    end

    def create_tables
      create_dataclip_results_table
      create_schema_cache_table
      create_cache_stats_table
    end

    def create_dataclip_results_table
      return if CACHE_DB.table_exists?(:dataclip_results)

      CACHE_DB.create_table :dataclip_results do
        String :cache_key, primary_key: true
        String :dataclip_slug, null: true # For dataclip-specific queries
        String :query_hash, null: false # SHA256 hash of the SQL query
        Text :sql_query, null: false # Store original query for debugging
        Text :result_data, null: false # JSON serialized results
        Text :result_metadata, null: false # JSON with columns, row_count, execution_time
        String :parameters_hash, null: true # Hash of query parameters if any
        DateTime :cached_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :expires_at, null: false # Explicit expiration timestamp
        Integer :ttl_seconds, default: 3600 # TTL in seconds
        Integer :hit_count, default: 0 # Number of times this cache entry was used
        DateTime :last_accessed_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # Create indexes for better performance
      CACHE_DB.add_index :dataclip_results, :dataclip_slug
      CACHE_DB.add_index :dataclip_results, :query_hash
      CACHE_DB.add_index :dataclip_results, :expires_at
      CACHE_DB.add_index :dataclip_results, :cached_at

      puts '  - Created dataclip_results cache table with indexes'
    end

    def create_schema_cache_table
      return if CACHE_DB.table_exists?(:schema_cache)

      CACHE_DB.create_table :schema_cache do
        String :cache_key, primary_key: true
        String :connection_hash, null: false # Hash of connection URL for different databases
        Text :schema_data, null: false # JSON serialized schema results
        Text :schema_metadata, null: false # JSON with table count, fetch time, etc.
        DateTime :cached_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :expires_at, null: false # Explicit expiration timestamp
        Integer :ttl_seconds, default: 7200 # 2 hours default TTL (schema changes less frequently)
        Integer :hit_count, default: 0 # Number of times this cache entry was used
        DateTime :last_accessed_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # Create indexes for better performance
      CACHE_DB.add_index :schema_cache, :connection_hash
      CACHE_DB.add_index :schema_cache, :expires_at
      CACHE_DB.add_index :schema_cache, :cached_at

      puts '  - Created schema_cache table with indexes'
    end

    def create_cache_stats_table
      return if CACHE_DB.table_exists?(:cache_stats)

      CACHE_DB.create_table :cache_stats do
        primary_key :id
        String :metric_name, null: false
        String :metric_value, null: false
        DateTime :recorded_at, default: Sequel::CURRENT_TIMESTAMP
      end

      CACHE_DB.add_index :cache_stats, :metric_name
      CACHE_DB.add_index :cache_stats, :recorded_at

      puts '  - Created cache_stats table'
    end

    def setup_helper_methods
      Object.class_eval do
        # Generate cache key for dataclip results
        def generate_dataclip_cache_key(sql_query, parameters = nil, dataclip_slug = nil)
          query_hash = Digest::SHA256.hexdigest(sql_query.strip.downcase)
          params_hash = parameters ? Digest::SHA256.hexdigest(parameters.to_json) : nil

          key_parts = [query_hash]
          key_parts << params_hash if params_hash
          key_parts << dataclip_slug if dataclip_slug

          "dataclip:#{key_parts.join(':')}"
        end

        # Cache dataclip results in SQLite
        def cache_dataclip_result(sql_query, result_hash, dataclip_slug = nil, parameters = nil, ttl_seconds = 3600)
          cache_key = generate_dataclip_cache_key(sql_query, parameters, dataclip_slug)
          query_hash = Digest::SHA256.hexdigest(sql_query.strip.downcase)
          params_hash = parameters ? Digest::SHA256.hexdigest(parameters.to_json) : nil
          expires_at = Time.now + ttl_seconds

          # Separate result data from metadata
          result_data = {
            success: result_hash[:success],
            data: result_hash[:data],
            errors: result_hash[:errors] || []
          }

          result_metadata = {
            columns: result_hash[:columns],
            row_count: result_hash[:row_count],
            execution_time: result_hash[:execution_time]
          }

          CACHE_DB[:dataclip_results].insert_conflict(:replace).insert(
            cache_key: cache_key,
            dataclip_slug: dataclip_slug,
            query_hash: query_hash,
            sql_query: sql_query,
            result_data: result_data.to_json,
            result_metadata: result_metadata.to_json,
            parameters_hash: params_hash,
            cached_at: Time.now,
            expires_at: expires_at,
            ttl_seconds: ttl_seconds,
            hit_count: 0,
            last_accessed_at: Time.now
          )

          record_cache_stat('cache_writes', '1')
          cache_key
        end

        # Get cached dataclip result from SQLite
        def get_cached_dataclip_result(sql_query, parameters = nil, dataclip_slug = nil)
          cache_key = generate_dataclip_cache_key(sql_query, parameters, dataclip_slug)
          cached = CACHE_DB[:dataclip_results].where(cache_key: cache_key).first

          return nil unless cached

          # Check if cache is expired
          if Time.now > cached[:expires_at]
            CACHE_DB[:dataclip_results].where(cache_key: cache_key).delete
            record_cache_stat('cache_expiries', '1')
            return nil
          end

          # Update hit count and last accessed time
          CACHE_DB[:dataclip_results].where(cache_key: cache_key).update(
            hit_count: cached[:hit_count] + 1,
            last_accessed_at: Time.now
          )

          # Reconstruct full result hash
          result_data = JSON.parse(cached[:result_data], symbolize_names: true)
          result_metadata = JSON.parse(cached[:result_metadata], symbolize_names: true)

          record_cache_stat('cache_hits', '1')

          result_data.merge(result_metadata).merge(
            cached: true,
            cache_key: cache_key,
            cached_at: cached[:cached_at]
          )
        end

        # Invalidate cache entries for a specific dataclip
        def invalidate_dataclip_cache(dataclip_slug)
          deleted_count = CACHE_DB[:dataclip_results].where(dataclip_slug: dataclip_slug).delete
          record_cache_stat('cache_invalidations', deleted_count.to_s)
          deleted_count
        end

        # Invalidate cache entries by query hash
        def invalidate_query_cache(sql_query)
          query_hash = Digest::SHA256.hexdigest(sql_query.strip.downcase)
          deleted_count = CACHE_DB[:dataclip_results].where(query_hash: query_hash).delete
          record_cache_stat('cache_invalidations', deleted_count.to_s)
          deleted_count
        end

        # Clear expired cache entries
        def clear_expired_dataclip_cache
          deleted_count = CACHE_DB[:dataclip_results].where(
            Sequel.lit('expires_at < datetime("now")')
          ).delete
          record_cache_stat('expired_entries_cleared', deleted_count.to_s)
          deleted_count
        end

        # Clear all cache entries
        def clear_all_dataclip_cache
          deleted_count = CACHE_DB[:dataclip_results].delete
          record_cache_stat('full_cache_clear', '1')
          deleted_count
        end

        # Get cache statistics
        def get_dataclip_cache_stats
          total_entries = CACHE_DB[:dataclip_results].count
          expired_entries = CACHE_DB[:dataclip_results].where(
            Sequel.lit('expires_at < datetime("now")')
          ).count

          hit_stats = CACHE_DB[:dataclip_results].select(
            Sequel.function(:sum, :hit_count).as(:total_hits),
            Sequel.function(:avg, :hit_count).as(:avg_hits_per_entry),
            Sequel.function(:max, :hit_count).as(:max_hits)
          ).first

          size_stats = CACHE_DB[:dataclip_results].select(
            Sequel.function(:sum, Sequel.function(:length, :result_data)).as(:total_data_size),
            Sequel.function(:avg, Sequel.function(:length, :result_data)).as(:avg_entry_size)
          ).first

          {
            total_entries: total_entries,
            expired_entries: expired_entries,
            active_entries: total_entries - expired_entries,
            total_hits: hit_stats[:total_hits] || 0,
            avg_hits_per_entry: hit_stats[:avg_hits_per_entry]&.round(2) || 0,
            max_hits: hit_stats[:max_hits] || 0,
            total_data_size_bytes: size_stats[:total_data_size] || 0,
            avg_entry_size_bytes: size_stats[:avg_entry_size]&.round(0) || 0,
            cache_hit_ratio: calculate_cache_hit_ratio
          }
        end

        # Get top cached queries by hit count
        def get_top_cached_queries(limit = 10)
          CACHE_DB[:dataclip_results]
            .select(:dataclip_slug, :sql_query, :hit_count, :cached_at, :last_accessed_at)
            .order(Sequel.desc(:hit_count))
            .limit(limit)
            .all
        end

        # Schema caching methods
        # Generate cache key for schema results
        def generate_schema_cache_key(connection_url)
          connection_hash = Digest::SHA256.hexdigest(sanitize_connection_url(connection_url))
          "schema:#{connection_hash}"
        end

        # Cache schema results in SQLite
        def cache_schema_result(connection_url, result_hash, ttl_seconds = 7200)
          cache_key = generate_schema_cache_key(connection_url)
          connection_hash = Digest::SHA256.hexdigest(sanitize_connection_url(connection_url))
          expires_at = Time.now + ttl_seconds

          # Separate result data from metadata
          schema_data = {
            success: result_hash[:success],
            schema: result_hash[:schema],
            errors: result_hash[:errors] || []
          }

          # Calculate metadata
          table_count = result_hash[:schema]&.keys&.length || 0
          total_columns = result_hash[:schema]&.values&.map { |table| table[:column_count] || 0 }&.sum || 0

          schema_metadata = {
            table_count: table_count,
            total_columns: total_columns,
            fetch_time: result_hash[:fetch_time] || 0
          }

          CACHE_DB[:schema_cache].insert_conflict(:replace).insert(
            cache_key: cache_key,
            connection_hash: connection_hash,
            schema_data: schema_data.to_json,
            schema_metadata: schema_metadata.to_json,
            cached_at: Time.now,
            expires_at: expires_at,
            ttl_seconds: ttl_seconds,
            hit_count: 0,
            last_accessed_at: Time.now
          )

          record_cache_stat('schema_cache_writes', '1')
          cache_key
        end

        # Get cached schema result from SQLite
        def get_cached_schema_result(connection_url)
          cache_key = generate_schema_cache_key(connection_url)
          cached = CACHE_DB[:schema_cache].where(cache_key: cache_key).first

          return nil unless cached

          # Check if cache is expired
          if Time.now > cached[:expires_at]
            CACHE_DB[:schema_cache].where(cache_key: cache_key).delete
            record_cache_stat('schema_cache_expiries', '1')
            return nil
          end

          # Update hit count and last accessed time
          CACHE_DB[:schema_cache].where(cache_key: cache_key).update(
            hit_count: cached[:hit_count] + 1,
            last_accessed_at: Time.now
          )

          # Reconstruct full result hash
          schema_data = JSON.parse(cached[:schema_data], symbolize_names: true)
          schema_metadata = JSON.parse(cached[:schema_metadata], symbolize_names: true)

          record_cache_stat('schema_cache_hits', '1')

          # Convert schema keys back to strings to match original format
          converted_schema = {}
          if schema_data[:schema].is_a?(Hash)
            schema_data[:schema].each do |key, value|
              converted_schema[key.to_s] = value
            end
            schema_data[:schema] = converted_schema
          end

          schema_data.merge(
            cached: true,
            cache_key: cache_key,
            cached_at: cached[:cached_at],
            table_count: schema_metadata[:table_count],
            total_columns: schema_metadata[:total_columns]
          )
        end

        # Clear expired schema cache entries
        def clear_expired_schema_cache
          deleted_count = CACHE_DB[:schema_cache].where(
            Sequel.lit('expires_at < datetime("now")')
          ).delete
          record_cache_stat('expired_schema_entries_cleared', deleted_count.to_s)
          deleted_count
        end

        # Clear all schema cache entries
        def clear_all_schema_cache
          deleted_count = CACHE_DB[:schema_cache].delete
          record_cache_stat('full_schema_cache_clear', '1')
          deleted_count
        end

        # Get schema cache statistics
        def get_schema_cache_stats
          total_entries = CACHE_DB[:schema_cache].count
          expired_entries = CACHE_DB[:schema_cache].where(
            Sequel.lit('expires_at < datetime("now")')
          ).count

          hit_stats = CACHE_DB[:schema_cache].select(
            Sequel.function(:sum, :hit_count).as(:total_hits),
            Sequel.function(:avg, :hit_count).as(:avg_hits_per_entry),
            Sequel.function(:max, :hit_count).as(:max_hits)
          ).first

          size_stats = CACHE_DB[:schema_cache].select(
            Sequel.function(:sum, Sequel.function(:length, :schema_data)).as(:total_data_size),
            Sequel.function(:avg, Sequel.function(:length, :schema_data)).as(:avg_entry_size)
          ).first

          {
            total_entries: total_entries,
            expired_entries: expired_entries,
            active_entries: total_entries - expired_entries,
            total_hits: hit_stats[:total_hits] || 0,
            avg_hits_per_entry: hit_stats[:avg_hits_per_entry]&.round(2) || 0,
            max_hits: hit_stats[:max_hits] || 0,
            total_data_size_bytes: size_stats[:total_data_size] || 0,
            avg_entry_size_bytes: size_stats[:avg_entry_size]&.round(0) || 0,
            cache_hit_ratio: calculate_schema_cache_hit_ratio
          }
        end

        # Get top cached schemas by hit count
        def get_top_cached_schemas(limit = 10)
          CACHE_DB[:schema_cache]
            .select(:connection_hash, :hit_count, :cached_at, :last_accessed_at)
            .order(Sequel.desc(:hit_count))
            .limit(limit)
            .all
        end

        private

        # Record cache statistics
        def record_cache_stat(metric_name, metric_value)
          CACHE_DB[:cache_stats].insert(
            metric_name: metric_name,
            metric_value: metric_value.to_s,
            recorded_at: Time.now
          )
        rescue StandardError
          # Fail silently for stats to avoid breaking main functionality
        end

        # Calculate cache hit ratio from recent stats
        def calculate_cache_hit_ratio
          recent_stats = CACHE_DB[:cache_stats]
            .where(metric_name: ['cache_hits', 'cache_writes'])
            .where(Sequel.lit('recorded_at > datetime("now", "-1 hour")'))
            .group(:metric_name)
            .select(:metric_name, Sequel.function(:count, '*').as(:count))
            .all
            .each_with_object({}) { |row, hash| hash[row[:metric_name]] = row[:count] }

          hits = recent_stats['cache_hits'] || 0
          writes = recent_stats['cache_writes'] || 0
          total_requests = hits + writes

          return 0.0 if total_requests == 0
          (hits.to_f / total_requests * 100).round(2)
        end

        # Calculate schema cache hit ratio from recent stats
        def calculate_schema_cache_hit_ratio
          recent_stats = CACHE_DB[:cache_stats]
            .where(metric_name: ['schema_cache_hits', 'schema_cache_writes'])
            .where(Sequel.lit('recorded_at > datetime("now", "-1 hour")'))
            .group(:metric_name)
            .select(:metric_name, Sequel.function(:count, '*').as(:count))
            .all
            .each_with_object({}) { |row, hash| hash[row[:metric_name]] = row[:count] }

          hits = recent_stats['schema_cache_hits'] || 0
          writes = recent_stats['schema_cache_writes'] || 0
          total_requests = hits + writes

          return 0.0 if total_requests == 0
          (hits.to_f / total_requests * 100).round(2)
        end

        # Sanitize connection URL for hashing (remove sensitive info)
        def sanitize_connection_url(connection_url)
          # Remove password from URL for hashing while keeping host/port/database
          uri = URI.parse(connection_url)
          uri.password = nil if uri.password
          uri.to_s
        rescue StandardError
          # If URL parsing fails, just hash the whole thing
          connection_url
        end
      end
    end

    puts '  - SQLite dataclip and schema cache helper methods loaded'
  end
end
