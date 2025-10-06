# frozen_string_literal: true

require 'sequel'
require 'logger'

# PostgreSQL database initializer
module PostgreSQLInitializer
  class << self
    def setup!
      establish_connection
      # Don't create tables here - let migrations handle table creation
      # create_tables
      setup_helper_methods
      puts '✓ PostgreSQL database initialized'
    end

    private

    def establish_connection
      database_url = ENV['DATABASE_URL']
      raise 'DATABASE_URL environment variable is required' unless database_url

      connection = Sequel.connect(
        database_url,
        max_connections: ENV.fetch('DB_MAX_CONNECTIONS', 10).to_i,
        logger: setup_logger,
        test: false, # Don't test connection on startup
        pool_timeout: 5
      )

      Object.const_set(:DB, connection)

      # Enable UUID extension if not already enabled
      enable_uuid_extension

      puts "  - PostgreSQL: #{DB.opts[:database] || 'Connected'}"
    end

    def enable_uuid_extension
      DB.run('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
    rescue Sequel::DatabaseError => e
      puts "  - Warning: Could not enable UUID extension: #{e.message}"
    end

    def create_tables
      # Only try to create tables if we can connect to the database
      # This prevents errors during rake db:create when database doesn't exist yet
      create_dataclips_table
    rescue Sequel::DatabaseError => e
      puts "  - Warning: Could not create tables: #{e.message}"
    end

    def create_dataclips_table
      return if DB.table_exists?(:dataclips)

      DB.create_table :dataclips do
        primary_key :uuid, :uuid, default: Sequel.function(:uuid_generate_v4)
        String :slug, null: false
        String :title, null: false
        Text :description
        Text :sql_query, null: false
        String :created_by
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

        index :slug
        index :created_by
      end
      puts '  - Created dataclips table'
    end

    def setup_helper_methods
      Object.class_eval do
        # Store a dataclip in PostgreSQL
        def create_dataclip(slug, title, sql_query, created_by = nil)
          DB[:dataclips].insert(
            slug: slug,
            title: title,
            sql_query: sql_query,
            created_by: created_by,
            created_at: Time.now,
            updated_at: Time.now
          )
        end

        # Get a dataclip from PostgreSQL
        def get_dataclip(slug)
          DB[:dataclips].where(slug: slug).first
        end

        # Get all dataclips from PostgreSQL
        def get_all_dataclips
          DB[:dataclips].order(:created_at).all
        end

        # Update a dataclip in PostgreSQL
        def update_dataclip(slug, updates)
          updates[:updated_at] = Time.now
          DB[:dataclips].where(slug: slug).update(updates)
        end

        # Delete a dataclip from PostgreSQL
        def delete_dataclip(slug)
          DB[:dataclips].where(slug: slug).delete
        end

        # Upsert an addon (insert or update if exists)
        def upsert_addon(uuid, name)
          existing = DB[:addons].where(uuid: uuid).first

          if existing
            DB[:addons].where(uuid: uuid).update(
              name: name,
              updated_at: Time.now
            )
          else
            DB[:addons].insert(
              uuid: uuid,
              name: name,
              created_at: Time.now,
              updated_at: Time.now
            )
          end
        end

        # Get an addon by UUID
        def get_addon(uuid)
          DB[:addons].where(uuid: uuid).first
        end

        # Get all addons from PostgreSQL
        def get_all_addons
          DB[:addons].order(:name).all
        end

        # Delete an addon by UUID
        def delete_addon(uuid)
          DB[:addons].where(uuid: uuid).delete
        end
      end

      puts '  - PostgreSQL helper methods loaded'
    end

    def setup_logger
      return nil if ENV['RACK_ENV'] == 'test'

      logger = Logger.new($stdout)
      logger.level = ENV['LOG_LEVEL'] == 'debug' ? Logger::DEBUG : Logger::INFO
      logger
    end
  end
end
