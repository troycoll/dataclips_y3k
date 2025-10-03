# frozen_string_literal: true

require 'sequel'
require 'logger'

# ClipWorker executes dataclip SQL queries against the DATABASE_URL
class ClipWorker
  class << self
    # Execute a dataclip SQL query and return results
    # @param sql_query [String] The SQL query to execute
    # @param connection_url [String] Optional database URL, defaults to ENV['DATABASE_URL']
    # @return [Hash] Result hash with success status, data, and any errors
    def execute(sql_query, connection_url = nil)
      connection_url ||= ENV['DATABASE_URL']

      validate_inputs!(sql_query, connection_url)

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
    # @return [Hash] Result hash with success status, data, and any errors
    def execute_dataclip(slug, connection_url = nil)
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

      execute(dataclip[:sql_query], connection_url)
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
  end
end
