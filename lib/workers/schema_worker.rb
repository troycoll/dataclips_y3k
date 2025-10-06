# frozen_string_literal: true

require 'sequel'
require 'logger'

# SchemaWorker fetches PostgreSQL database schema information from DATABASE_URL
class SchemaWorker
  class << self
    # Fetch PostgreSQL database schema information (user-defined tables with columns and types)
    # @param connection_url [String] Optional database URL, defaults to ENV['DATABASE_URL']
    # @param cache_enabled [Boolean] Whether to use caching (defaults to system config)
    # @param cache_ttl [Integer] Cache TTL in seconds (defaults to system config)
    # @return [Hash] Result hash with success status, schema data, and any errors
    def fetch_schema(connection_url = :default, cache_enabled: nil, cache_ttl: nil)
      # Handle explicitly passed nil vs default parameter
      connection_url = ENV['DATABASE_URL'] if connection_url == :default
      cache_enabled = cache_enabled.nil? ? schema_caching_enabled? : cache_enabled
      cache_ttl ||= default_schema_cache_ttl

      validate_connection_url!(connection_url)

      # Try to get cached result if caching is enabled
      if cache_enabled
        cached_result = SchemaCache.get_result(connection_url)
        if cached_result
          log_cache_hit(connection_url)
          return cached_result
        end
      end

      result = {
        success: false,
        schema: {},
        errors: []
      }

      start_time = Time.now

      begin
        # Create a separate connection for the worker to avoid interfering with main app
        db = Sequel.connect(connection_url, logger: setup_logger)

        # Get all user-defined tables (excluding system tables)
        tables = get_user_tables(db)

        schema_data = {}
        tables.each do |table_name|
          schema_data[table_name] = get_table_schema(db, table_name)
        end

        result[:success] = true
        result[:schema] = schema_data
        result[:fetch_time] = ((Time.now - start_time) * 1000).round(2) # milliseconds

        # Cache the result if caching is enabled and fetch was successful
        if cache_enabled && result[:success]
          SchemaCache.cache_result(connection_url, result, ttl_seconds: cache_ttl)
          log_cache_write(connection_url)
        end

        log_schema_fetch(tables.length, result[:fetch_time])
      rescue Sequel::DatabaseError => e
        result[:errors] << "Database error: #{e.message}"
        log_error(e)
      rescue StandardError => e
        result[:errors] << "Schema fetch error: #{e.message}"
        log_error(e)
      ensure
        db&.disconnect
      end

      result
    end

    # Clear schema cache
    def clear_cache
      return 0 unless schema_caching_enabled?

      SchemaCache.clear_all
    end

    # Get schema cache statistics
    def cache_stats
      return {} unless schema_caching_enabled?

      SchemaCache.stats
    end

    # Clear expired schema cache entries
    def cleanup_cache
      return 0 unless schema_caching_enabled?

      SchemaCache.clear_expired
    end

    private

    def validate_connection_url!(connection_url)
      raise ArgumentError, 'Database connection URL is required' if connection_url.nil? || connection_url.strip.empty?
    end

    def get_user_tables(db)
      # Get PostgreSQL user-defined tables, filtering out system tables and views
      db.fetch(<<~SQL).map { |row| row[:table_name] }
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
        AND table_name NOT LIKE 'pg_%'
        AND table_name NOT LIKE 'sql_%'
        ORDER BY table_name
      SQL
    end

    def get_table_schema(db, table_name)
      columns = []

      begin
        # Use Sequel's schema method to get column information
        schema_info = db.schema(table_name.to_sym)

        schema_info.each do |column_name, column_info|
          columns << {
            name: column_name.to_s,
            type: format_column_type(column_info[:type], column_info),
            nullable: column_info[:allow_null],
            primary_key: column_info[:primary_key] || false,
            default: column_info[:default]
          }
        end
      rescue StandardError
        # If schema inspection fails, try database-specific queries
        columns = get_table_schema_fallback(db, table_name)
      end

      {
        columns: columns,
        column_count: columns.length
      }
    end

    def get_table_schema_fallback(db, table_name)
      # PostgreSQL-specific fallback query
      get_postgres_table_schema(db, table_name)
    end

    def get_postgres_table_schema(db, table_name)
      db.fetch(<<~SQL, table_name).map do |row|
        SELECT
          column_name,
          data_type,
          is_nullable,
          column_default,
          CASE
            WHEN constraint_type = 'PRIMARY KEY' THEN true
            ELSE false
          END as is_primary_key
        FROM information_schema.columns c
        LEFT JOIN information_schema.key_column_usage kcu
          ON c.table_name = kcu.table_name AND c.column_name = kcu.column_name
        LEFT JOIN information_schema.table_constraints tc
          ON kcu.constraint_name = tc.constraint_name AND tc.constraint_type = 'PRIMARY KEY'
        WHERE c.table_name = ? AND c.table_schema = 'public'
        ORDER BY c.ordinal_position
      SQL
        {
          name: row[:column_name],
          type: row[:data_type],
          nullable: row[:is_nullable] == 'YES',
          primary_key: row[:is_primary_key],
          default: row[:column_default]
        }
      end
    rescue StandardError
      []
    end

    def format_column_type(type, column_info)
      # Format the column type for display
      case type
      when :string, :varchar
        max_length = column_info[:max_length]
        max_length ? "varchar(#{max_length})" : 'varchar'
      when :text
        'text'
      when :integer
        'integer'
      when :bigint
        'bigint'
      when :decimal, :numeric
        precision = column_info[:precision]
        scale = column_info[:scale]
        if precision && scale
          "decimal(#{precision},#{scale})"
        elsif precision
          "decimal(#{precision})"
        else
          'decimal'
        end
      when :float
        'float'
      when :double
        'double'
      when :boolean
        'boolean'
      when :date
        'date'
      when :datetime, :timestamp
        'timestamp'
      when :time
        'time'
      when :uuid
        'uuid'
      when :json, :jsonb
        type.to_s
      else
        type.to_s
      end
    end

    def setup_logger
      return nil if ENV['RACK_ENV'] == 'test'

      logger = Logger.new($stdout)
      logger.level = ENV['LOG_LEVEL'] == 'debug' ? Logger::DEBUG : Logger::WARN
      logger
    end

    def log_schema_fetch(table_count, fetch_time = nil)
      return if ENV['RACK_ENV'] == 'test'

      time_info = fetch_time ? " (#{fetch_time}ms)" : ''
      puts "[SchemaWorker] Fetched schema for #{table_count} tables#{time_info}"
    end

    def log_error(error)
      return if ENV['RACK_ENV'] == 'test'

      puts "[SchemaWorker] Error fetching schema: #{error.message}"
    end

    def log_cache_hit(connection_url)
      return if ENV['RACK_ENV'] == 'test'

      conn_info = sanitize_connection_for_log(connection_url)
      puts "[SchemaWorker] Cache HIT: #{conn_info}"
    end

    def log_cache_write(connection_url)
      return if ENV['RACK_ENV'] == 'test'

      conn_info = sanitize_connection_for_log(connection_url)
      puts "[SchemaWorker] Cache WRITE: #{conn_info}"
    end

    # Check if schema caching is enabled
    def schema_caching_enabled?
      return false unless defined?(SQLiteInitializer)

      SQLiteInitializer.schema_caching_enabled?
    rescue StandardError
      false
    end

    # Get default schema cache TTL
    def default_schema_cache_ttl
      return 7200 unless defined?(SQLiteInitializer)

      SQLiteInitializer.cache_config[:schema_default_ttl]
    rescue StandardError
      7200
    end

    # Sanitize connection URL for logging (remove sensitive info)
    def sanitize_connection_for_log(connection_url)
      uri = URI.parse(connection_url)

      # Check if this looks like a valid database URL
      # Database URLs should have a scheme and host
      return 'database' unless uri.scheme && uri.host

      uri.password = '***' if uri.password
      uri.to_s
    rescue StandardError
      'database'
    end
  end
end
