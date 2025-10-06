# frozen_string_literal: true

require 'sequel'
require 'logger'

# ClipWorker executes dataclip SQL queries against the DATABASE_URL
class ClipWorker
  class << self
    # Execute a dataclip SQL query and return results
    # @param sql_query [String] The SQL query to execute
    # @param connection_url [String] Optional database URL, defaults to ENV['DATABASE_URL']
    # @param cache_enabled [Boolean] Whether to use caching (defaults to system config)
    # @param cache_ttl [Integer] Cache TTL in seconds (defaults to system config)
    # @return [Hash] Result hash with success status, data, and any errors
    def execute(sql_query, connection_url = nil, cache_enabled: nil, cache_ttl: nil)
      connection_url ||= ENV['DATABASE_URL']
      cache_enabled = cache_enabled.nil? ? caching_enabled? : cache_enabled
      cache_ttl ||= default_cache_ttl

      validate_inputs!(sql_query, connection_url)

      # Try to get cached result if caching is enabled
      if cache_enabled
        cached_result = DataclipCache.get_result(sql_query)
        if cached_result
          log_cache_hit(sql_query)
          return cached_result
        end
      end

      result = {
        success: false,
        data: [],
        columns: [],
        row_count: 0,
        execution_time: 0,
        errors: []
      }

      start_time = Time.now

      begin
        # Create a separate connection for the worker to avoid interfering with main app
        db = Sequel.connect(connection_url, logger: setup_logger)

        # Execute the query and fetch results
        dataset = db[sql_query]
        rows = dataset.all

        # Get column information from the first row or dataset
        columns = if rows.any?
                    rows.first.keys.map(&:to_s)
                  else
                    # For queries that return no rows, try to get columns from dataset
                    begin
                      dataset.columns.map(&:to_s)
                    rescue StandardError
                      []
                    end
                  end

        result[:success] = true
        result[:data] = rows
        result[:columns] = columns
        result[:row_count] = rows.length
        result[:execution_time] = ((Time.now - start_time) * 1000).round(2) # milliseconds

        # Cache the result if caching is enabled and query was successful
        if cache_enabled && result[:success]
          DataclipCache.cache_result(sql_query, result, ttl_seconds: cache_ttl)
          log_cache_write(sql_query)
        end

        log_execution(sql_query, result[:row_count], result[:execution_time])
      rescue Sequel::DatabaseError => e
        result[:errors] << "Database error: #{e.message}"
        log_error(sql_query, e)
      rescue StandardError => e
        result[:errors] << "Execution error: #{e.message}"
        log_error(sql_query, e)
      ensure
        db&.disconnect
      end

      result
    end

    # Execute a dataclip by slug
    # @param slug [String] The dataclip slug to execute
    # @param connection_url [String] Optional database URL for query execution
    # @param cache_enabled [Boolean] Whether to use caching (defaults to system config)
    # @param cache_ttl [Integer] Cache TTL in seconds (defaults to system config)
    # @return [Hash] Result hash with success status, data, and any errors
    def execute_dataclip(slug, connection_url = nil, cache_enabled: nil, cache_ttl: nil)
      cache_enabled = cache_enabled.nil? ? caching_enabled? : cache_enabled
      cache_ttl ||= default_cache_ttl

      # Get the dataclip from the main database connection
      dataclip = get_dataclip(slug)

      unless dataclip
        return {
          success: false,
          data: [],
          columns: [],
          row_count: 0,
          execution_time: 0,
          errors: ["Dataclip with slug '#{slug}' not found"]
        }
      end

      # Try to get cached result if caching is enabled
      if cache_enabled
        cached_result = DataclipCache.get_result(dataclip[:sql_query], dataclip_slug: slug)
        if cached_result
          log_cache_hit(dataclip[:sql_query], slug)
          return cached_result
        end
      end

      # Execute the query
      result = execute(dataclip[:sql_query], connection_url, cache_enabled: false) # Avoid double caching

      # Cache with dataclip slug if successful and caching enabled
      if cache_enabled && result[:success]
        DataclipCache.cache_result(dataclip[:sql_query], result, dataclip_slug: slug, ttl_seconds: cache_ttl)
        log_cache_write(dataclip[:sql_query], slug)
      end

      result
    end

    # Invalidate cache for a specific dataclip
    def invalidate_cache(slug)
      return 0 unless caching_enabled?

      DataclipCache.invalidate_by_slug(slug)
    end

    # Get cache statistics
    def cache_stats
      return {} unless caching_enabled?

      DataclipCache.stats
    end

    # Clear expired cache entries
    def cleanup_cache
      return 0 unless caching_enabled?

      DataclipCache.clear_expired
    end

    private

    def validate_inputs!(sql_query, connection_url)
      raise ArgumentError, 'SQL query cannot be empty' if sql_query.nil? || sql_query.strip.empty?
      raise ArgumentError, 'Database connection URL is required' if connection_url.nil? || connection_url.strip.empty?

      # Basic SQL injection prevention - reject queries with dangerous patterns
      dangerous_patterns = [
        /\b(drop|truncate|delete|alter|create|insert|update)\s+/i,
        /;\s*(drop|truncate|delete|alter|create|insert|update)/i
      ]

      dangerous_patterns.each do |pattern|
        raise ArgumentError, 'Query contains potentially dangerous SQL operations' if sql_query.match?(pattern)
      end
    end

    def setup_logger
      return nil if ENV['RACK_ENV'] == 'test'

      logger = Logger.new($stdout)
      logger.level = ENV['LOG_LEVEL'] == 'debug' ? Logger::DEBUG : Logger::WARN
      logger
    end

    def log_execution(sql_query, row_count, execution_time)
      return if ENV['RACK_ENV'] == 'test'

      puts "[ClipWorker] Executed query (#{execution_time}ms, #{row_count} rows): #{sql_query.strip[0..100]}#{if sql_query.length > 100
                                                                                                                '...'
                                                                                                              end}"
    end

    def log_error(sql_query, error)
      return if ENV['RACK_ENV'] == 'test'

      puts "[ClipWorker] Error executing query: #{sql_query.strip[0..100]}#{'...' if sql_query.length > 100}"
      puts "[ClipWorker] Error: #{error.message}"
    end

    def log_cache_hit(sql_query, slug = nil)
      return if ENV['RACK_ENV'] == 'test'

      slug_info = slug ? " (slug: #{slug})" : ''
      puts "[ClipWorker] Cache HIT#{slug_info}: #{sql_query.strip[0..60]}#{'...' if sql_query.length > 60}"
    end

    def log_cache_write(sql_query, slug = nil)
      return if ENV['RACK_ENV'] == 'test'

      slug_info = slug ? " (slug: #{slug})" : ''
      puts "[ClipWorker] Cache WRITE#{slug_info}: #{sql_query.strip[0..60]}#{'...' if sql_query.length > 60}"
    end

    # Check if caching is enabled
    def caching_enabled?
      return false unless defined?(SQLiteInitializer)

      SQLiteInitializer.caching_enabled?
    rescue StandardError
      false
    end

    # Get default cache TTL
    def default_cache_ttl
      return 3600 unless defined?(SQLiteInitializer)

      SQLiteInitializer.cache_config[:default_ttl]
    rescue StandardError
      3600
    end
  end
end
