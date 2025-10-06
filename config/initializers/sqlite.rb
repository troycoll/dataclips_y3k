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

    # Reset cache for testing - clears all tables and resets module instances
    def reset_cache!
      return unless defined?(CACHE_DB)

      # Clear all cache tables
      CACHE_DB[:dataclip_results].delete if CACHE_DB.table_exists?(:dataclip_results)
      CACHE_DB[:schema_cache].delete if CACHE_DB.table_exists?(:schema_cache)
      CACHE_DB[:cache_stats].delete if CACHE_DB.table_exists?(:cache_stats)

      # Reset module-level database references to ensure fresh state
      DataclipCache.db = CACHE_DB if defined?(DataclipCache)
      SchemaCache.db = CACHE_DB if defined?(SchemaCache)
      CacheStats.db = CACHE_DB if defined?(CacheStats)
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
      # Load cache modules
      puts '  - SQLite cache modules loaded'
    end
  end
end

# Dedicated module for dataclip result caching
module DataclipCache
  class << self
    attr_writer :db

    def db
      @db ||= CACHE_DB
    end

    # Cache a dataclip result
    def cache_result(sql_query, result_hash, dataclip_slug: nil, parameters: nil, ttl_seconds: 3600)
      cache_key = generate_cache_key(sql_query, parameters: parameters, dataclip_slug: dataclip_slug)
      query_hash = hash_query(sql_query)
      params_hash = parameters ? hash_parameters(parameters) : nil
      expires_at = Time.now + ttl_seconds

      result_data = extract_result_data(result_hash)
      result_metadata = extract_result_metadata(result_hash)

      db[:dataclip_results].insert_conflict(:replace).insert(
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

      CacheStats.record('cache_writes', '1')
      cache_key
    end

    # Retrieve a cached dataclip result
    def get_result(sql_query, parameters: nil, dataclip_slug: nil)
      cache_key = generate_cache_key(sql_query, parameters: parameters, dataclip_slug: dataclip_slug)
      cached = db[:dataclip_results].where(cache_key: cache_key).first

      return nil unless cached
      return nil if expired?(cached)

      update_hit_tracking(cache_key, cached)
      reconstruct_result(cached)
    end

    # Invalidate cache entries for a specific dataclip
    def invalidate_by_slug(dataclip_slug)
      deleted_count = db[:dataclip_results].where(dataclip_slug: dataclip_slug).delete
      CacheStats.record('cache_invalidations', deleted_count.to_s)
      deleted_count
    end

    # Invalidate cache entries by query
    def invalidate_by_query(sql_query)
      query_hash = hash_query(sql_query)
      deleted_count = db[:dataclip_results].where(query_hash: query_hash).delete
      CacheStats.record('cache_invalidations', deleted_count.to_s)
      deleted_count
    end

    # Clear expired cache entries
    def clear_expired
      deleted_count = db[:dataclip_results].where(
        Sequel.lit('expires_at < datetime("now")')
      ).delete
      CacheStats.record('expired_entries_cleared', deleted_count.to_s)
      deleted_count
    end

    # Clear all cache entries
    def clear_all
      deleted_count = db[:dataclip_results].delete
      CacheStats.record('full_cache_clear', '1')
      deleted_count
    end

    # Get cache statistics
    def stats
      total_entries = db[:dataclip_results].count
      expired_entries = db[:dataclip_results].where(
        Sequel.lit('expires_at < datetime("now")')
      ).count

      hit_stats = db[:dataclip_results].select(
        Sequel.function(:sum, :hit_count).as(:total_hits),
        Sequel.function(:avg, :hit_count).as(:avg_hits_per_entry),
        Sequel.function(:max, :hit_count).as(:max_hits)
      ).first

      size_stats = db[:dataclip_results].select(
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
        cache_hit_ratio: CacheStats.calculate_hit_ratio('cache_hits', 'cache_writes')
      }
    end

    # Get top cached queries by hit count
    def top_queries(limit = 10)
      db[:dataclip_results]
        .select(:dataclip_slug, :sql_query, :hit_count, :cached_at, :last_accessed_at)
        .order(Sequel.desc(:hit_count))
        .limit(limit)
        .all
    end

    private

    def generate_cache_key(sql_query, parameters: nil, dataclip_slug: nil)
      query_hash = hash_query(sql_query)
      params_hash = parameters ? hash_parameters(parameters) : nil

      key_parts = [query_hash]
      key_parts << params_hash if params_hash
      key_parts << dataclip_slug if dataclip_slug

      "dataclip:#{key_parts.join(':')}"
    end

    def hash_query(sql_query)
      Digest::SHA256.hexdigest(sql_query.strip.downcase)
    end

    def hash_parameters(parameters)
      Digest::SHA256.hexdigest(parameters.to_json)
    end

    def extract_result_data(result_hash)
      {
        success: result_hash[:success],
        data: result_hash[:data],
        errors: result_hash[:errors] || []
      }
    end

    def extract_result_metadata(result_hash)
      {
        columns: result_hash[:columns],
        row_count: result_hash[:row_count],
        execution_time: result_hash[:execution_time]
      }
    end

    def expired?(cached)
      if Time.now > cached[:expires_at]
        db[:dataclip_results].where(cache_key: cached[:cache_key]).delete
        CacheStats.record('cache_expiries', '1')
        true
      else
        false
      end
    end

    def update_hit_tracking(cache_key, cached)
      db[:dataclip_results].where(cache_key: cache_key).update(
        hit_count: cached[:hit_count] + 1,
        last_accessed_at: Time.now
      )
    end

    def reconstruct_result(cached)
      result_data = JSON.parse(cached[:result_data], symbolize_names: true)
      result_metadata = JSON.parse(cached[:result_metadata], symbolize_names: true)

      CacheStats.record('cache_hits', '1')

      result_data.merge(result_metadata).merge(
        cached: true,
        cache_key: cached[:cache_key],
        cached_at: cached[:cached_at]
      )
    end
  end
end

# Dedicated module for schema caching
module SchemaCache
  class << self
    attr_writer :db

    def db
      @db ||= CACHE_DB
    end

    # Cache a schema result
    def cache_result(connection_url, result_hash, ttl_seconds: 7200)
      cache_key = generate_cache_key(connection_url)
      connection_hash = hash_connection(connection_url)
      expires_at = Time.now + ttl_seconds

      schema_data = extract_schema_data(result_hash)
      schema_metadata = calculate_metadata(result_hash)

      db[:schema_cache].insert_conflict(:replace).insert(
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

      CacheStats.record('schema_cache_writes', '1')
      cache_key
    end

    # Retrieve a cached schema result
    def get_result(connection_url)
      cache_key = generate_cache_key(connection_url)
      cached = db[:schema_cache].where(cache_key: cache_key).first

      return nil unless cached
      return nil if expired?(cached)

      update_hit_tracking(cache_key, cached)
      reconstruct_result(cached)
    end

    # Clear expired schema cache entries
    def clear_expired
      deleted_count = db[:schema_cache].where(
        Sequel.lit('expires_at < datetime("now")')
      ).delete
      CacheStats.record('expired_schema_entries_cleared', deleted_count.to_s)
      deleted_count
    end

    # Clear all schema cache entries
    def clear_all
      deleted_count = db[:schema_cache].delete
      CacheStats.record('full_schema_cache_clear', '1')
      deleted_count
    end

    # Get schema cache statistics
    def stats
      total_entries = db[:schema_cache].count
      expired_entries = db[:schema_cache].where(
        Sequel.lit('expires_at < datetime("now")')
      ).count

      hit_stats = db[:schema_cache].select(
        Sequel.function(:sum, :hit_count).as(:total_hits),
        Sequel.function(:avg, :hit_count).as(:avg_hits_per_entry),
        Sequel.function(:max, :hit_count).as(:max_hits)
      ).first

      size_stats = db[:schema_cache].select(
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
        cache_hit_ratio: CacheStats.calculate_hit_ratio('schema_cache_hits', 'schema_cache_writes')
      }
    end

    # Get top cached schemas by hit count
    def top_schemas(limit = 10)
      db[:schema_cache]
        .select(:connection_hash, :hit_count, :cached_at, :last_accessed_at)
        .order(Sequel.desc(:hit_count))
        .limit(limit)
        .all
    end

    private

    def generate_cache_key(connection_url)
      connection_hash = hash_connection(connection_url)
      "schema:#{connection_hash}"
    end

    def hash_connection(connection_url)
      sanitized_url = sanitize_connection_url(connection_url)
      Digest::SHA256.hexdigest(sanitized_url)
    end

    def sanitize_connection_url(connection_url)
      # Remove password from URL for hashing while keeping host/port/database
      uri = URI.parse(connection_url)
      uri.password = nil if uri.password
      uri.to_s
    rescue StandardError
      # If URL parsing fails, just hash the whole thing
      connection_url
    end

    def extract_schema_data(result_hash)
      {
        success: result_hash[:success],
        schema: result_hash[:schema],
        errors: result_hash[:errors] || []
      }
    end

    def calculate_metadata(result_hash)
      table_count = result_hash[:schema]&.keys&.length || 0
      total_columns = result_hash[:schema]&.values&.map { |table| table[:column_count] || 0 }&.sum || 0

      {
        table_count: table_count,
        total_columns: total_columns,
        fetch_time: result_hash[:fetch_time] || 0
      }
    end

    def expired?(cached)
      if Time.now > cached[:expires_at]
        db[:schema_cache].where(cache_key: cached[:cache_key]).delete
        CacheStats.record('schema_cache_expiries', '1')
        true
      else
        false
      end
    end

    def update_hit_tracking(cache_key, cached)
      db[:schema_cache].where(cache_key: cache_key).update(
        hit_count: cached[:hit_count] + 1,
        last_accessed_at: Time.now
      )
    end

    def reconstruct_result(cached)
      schema_data = JSON.parse(cached[:schema_data], symbolize_names: true)
      schema_metadata = JSON.parse(cached[:schema_metadata], symbolize_names: true)

      CacheStats.record('schema_cache_hits', '1')

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
        cache_key: cached[:cache_key],
        cached_at: cached[:cached_at],
        table_count: schema_metadata[:table_count],
        total_columns: schema_metadata[:total_columns],
        fetch_time: schema_metadata[:fetch_time]
      )
    end
  end
end

# Dedicated module for cache statistics
module CacheStats
  class << self
    attr_writer :db

    def db
      @db ||= CACHE_DB
    end

    # Record a cache statistic
    def record(metric_name, metric_value)
      db[:cache_stats].insert(
        metric_name: metric_name,
        metric_value: metric_value.to_s,
        recorded_at: Time.now
      )
    rescue StandardError
      # Fail silently for stats to avoid breaking main functionality
    end

    # Calculate cache hit ratio from recent stats
    def calculate_hit_ratio(hit_metric, write_metric)
      recent_stats = db[:cache_stats]
        .where(metric_name: [hit_metric, write_metric])
        .where(Sequel.lit('recorded_at > datetime("now", "-1 hour")'))
        .group(:metric_name)
        .select(:metric_name, Sequel.function(:count, '*').as(:count))
        .all
        .each_with_object({}) { |row, hash| hash[row[:metric_name]] = row[:count] }

      hits = recent_stats[hit_metric] || 0
      writes = recent_stats[write_metric] || 0
      total_requests = hits + writes

      return 0.0 if total_requests == 0
      (hits.to_f / total_requests * 100).round(2)
    end
  end
end
