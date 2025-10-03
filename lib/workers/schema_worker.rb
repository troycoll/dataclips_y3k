# frozen_string_literal: true

require 'sequel'
require 'logger'

# SchemaWorker fetches PostgreSQL database schema information from DATABASE_URL
class SchemaWorker
  class << self
    # Fetch PostgreSQL database schema information (user-defined tables with columns and types)
    # @param connection_url [String] Optional database URL, defaults to ENV['DATABASE_URL']
    # @return [Hash] Result hash with success status, schema data, and any errors
    def fetch_schema(connection_url = :default)
      # Handle explicitly passed nil vs default parameter
      connection_url = ENV['DATABASE_URL'] if connection_url == :default

      validate_connection_url!(connection_url)

      result = {
        success: false,
        schema: {},
        errors: []
      }

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

        log_schema_fetch(tables.length)
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

    def log_schema_fetch(table_count)
      return if ENV['RACK_ENV'] == 'test'

      puts "[SchemaWorker] Fetched schema for #{table_count} tables"
    end

    def log_error(error)
      return if ENV['RACK_ENV'] == 'test'

      puts "[SchemaWorker] Error fetching schema: #{error.message}"
    end
  end
end
