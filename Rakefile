# frozen_string_literal: true

require 'sequel'
require 'uri'
require 'fileutils'

# Load .env file if it exists (before checking DATABASE_URL)
env_file = File.expand_path('.env', __dir__)
if File.exist?(env_file)
  begin
    require 'dotenv'
    Dotenv.load(env_file)
  rescue LoadError
    puts 'Warning: dotenv gem not available. Install it with: gem install dotenv'
  end
end

# Load config module but don't setup database connection yet
# This allows individual rake tasks to control when database setup happens
if ENV['DATABASE_URL']
  require_relative 'config/config'
  # NOTE: Config.setup! is called by individual tasks as needed, not here
end

# Database connection for admin tasks (connects to postgres/template1 for create/drop operations)
def admin_db_connection
  unless ENV['DATABASE_URL']
    puts 'Error: DATABASE_URL environment variable is required'
    exit 1
  end

  uri = URI.parse(ENV['DATABASE_URL'])
  admin_url = "#{uri.scheme}://#{uri.userinfo}@#{uri.host}:#{uri.port}/template1"
  Sequel.connect(admin_url)
end

# Extract database name from DATABASE_URL
def database_name
  unless ENV['DATABASE_URL']
    puts 'Error: DATABASE_URL environment variable is required'
    exit 1
  end

  uri = URI.parse(ENV['DATABASE_URL'])
  uri.path.sub('/', '')
end

# Ensure database connection is available
def ensure_db_connection
  return if defined?(DB) && DB

  if defined?(Config)
    Config.setup!
  else
    puts 'Error: Database connection not available. Make sure DATABASE_URL is set.'
    exit 1
  end
end

# Migration directory
MIGRATION_DIR = File.expand_path('db/migrate', __dir__)

namespace :db do
  desc 'Create the database'
  task :create do
    environment = ENV.fetch('RACK_ENV', 'development')

    if environment == 'production'
      puts '⚠️  Skipping database creation in production environment'
      puts '   Production databases should already exist and be managed externally'
      return
    end

    db_name = database_name

    begin
      admin_db = admin_db_connection

      # Check if database already exists
      existing_dbs = admin_db['SELECT datname FROM pg_database WHERE datname = ?', db_name].all

      if existing_dbs.any?
        puts "Database '#{db_name}' already exists"
      else
        admin_db.run("CREATE DATABASE \"#{db_name}\"")
        puts "Created database '#{db_name}'"
      end

      admin_db.disconnect
    rescue Sequel::DatabaseError => e
      puts "Error creating database: #{e.message}"
      exit 1
    end
  end

  desc 'Drop the database'
  task :drop do
    environment = ENV.fetch('RACK_ENV', 'development')

    if environment == 'production'
      puts '⚠️  Skipping database drop in production environment'
      puts '   Production databases should not be dropped'
      return
    end

    db_name = database_name

    begin
      admin_db = admin_db_connection

      # Terminate all connections to the database first
      admin_db.run(<<~SQL)
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '#{db_name}' AND pid <> pg_backend_pid()
      SQL

      # Check if database exists
      existing_dbs = admin_db['SELECT datname FROM pg_database WHERE datname = ?', db_name].all

      if existing_dbs.any?
        admin_db.run("DROP DATABASE \"#{db_name}\"")
        puts "Dropped database '#{db_name}'"
      else
        puts "Database '#{db_name}' does not exist"
      end

      admin_db.disconnect
    rescue Sequel::DatabaseError => e
      puts "Error dropping database: #{e.message}"
      exit 1
    end
  end

  desc 'Run database migrations'
  task :migrate do
    environment = ENV.fetch('RACK_ENV', 'development')
    ensure_db_connection

    unless Dir.exist?(MIGRATION_DIR)
      puts "Migration directory '#{MIGRATION_DIR}' does not exist"
      exit 1
    end

    begin
      Sequel.extension :migration

      if environment == 'production'
        puts '🔧 Running production migrations (dataclips table only)...'
        # In production, only run the dataclips migration
        dataclips_migration = File.join(MIGRATION_DIR, '001_create_dataclips.rb')
        if File.exist?(dataclips_migration)
          # Check if dataclips table already exists
          if DB.table_exists?(:dataclips)
            puts '   ✓ dataclips table already exists'
          else
            puts '   ⚙️  Creating dataclips table...'
            Sequel::Migrator.run(DB, MIGRATION_DIR, target: 1)
            puts '   ✅ dataclips table created successfully'
          end
        else
          puts '   ❌ dataclips migration file not found'
          exit 1
        end
      else
        puts "🔧 Running all migrations for #{environment} environment..."
        Sequel::Migrator.run(DB, MIGRATION_DIR)
        puts 'Database migrations completed successfully'
      end
    rescue Sequel::DatabaseError => e
      puts "Error running migrations: #{e.message}"
      exit 1
    end
  end

  desc 'Rollback last database migration'
  task :rollback do
    ensure_db_connection

    unless Dir.exist?(MIGRATION_DIR)
      puts "Migration directory '#{MIGRATION_DIR}' does not exist"
      exit 1
    end

    begin
      Sequel.extension :migration
      current_version = DB[:schema_migrations].max(:filename) if DB.table_exists?(:schema_migrations)

      if current_version
        # Get the previous migration version
        migrations = Dir[File.join(MIGRATION_DIR, '*.rb')].sort
        current_index = migrations.find_index { |m| File.basename(m, '.rb') == current_version }

        if current_index && current_index > 0
          target_version = File.basename(migrations[current_index - 1], '.rb')
          Sequel::Migrator.run(DB, MIGRATION_DIR, target: target_version.to_i)
          puts "Rolled back to migration: #{target_version}"
        else
          # Rollback to version 0 (no migrations)
          Sequel::Migrator.run(DB, MIGRATION_DIR, target: 0)
          puts 'Rolled back all migrations'
        end
      else
        puts 'No migrations to rollback'
      end
    rescue Sequel::DatabaseError => e
      puts "Error rolling back migration: #{e.message}"
      exit 1
    end
  end

  desc 'Seed the database with data'
  task :seed do
    environment = ENV.fetch('RACK_ENV', 'development')

    if environment == 'production'
      puts '⚠️  Skipping database seeding in production environment'
      puts '   Production databases should not be seeded with sample data'
      return
    end

    seed_file = File.expand_path('db/seeds.rb', __dir__)

    if File.exist?(seed_file)
      puts "🌱 Seeding #{environment} database with sample data..."
      load seed_file
    else
      puts "Seed file '#{seed_file}' does not exist"
    end
  end

  desc 'Setup the database (create, migrate, and seed)'
  task setup: %i[create migrate seed] do
    environment = ENV.fetch('RACK_ENV', 'development')
    puts "✅ Database setup completed successfully for #{environment} environment!"
  end

  desc 'Setup database for production (dataclips table only)'
  task :setup_production do
    environment = ENV.fetch('RACK_ENV', 'development')

    if environment != 'production'
      puts '⚠️  This task is intended for production environment only'
      puts "   Current environment: #{environment}"
      puts "   Use 'rake db:setup' for development/test environments"
      return
    end

    puts '🔧 Setting up dataclips for production environment...'
    puts '   - Skipping database creation (assuming pre-existing database)'
    puts '   - Creating dataclips table if needed'
    puts '   - Skipping data seeding'

    Rake::Task['db:migrate'].invoke
    puts '✅ Production database setup completed!'
  end

  namespace :schema do
    desc 'Dump the database schema'
    task :dump do
      ensure_db_connection

      schema_file = File.expand_path('db/schema.rb', __dir__)

      begin
        # Ensure db directory exists
        FileUtils.mkdir_p(File.dirname(schema_file))

        # Generate schema dump
        File.open(schema_file, 'w') do |file|
          file.puts '# frozen_string_literal: true'
          file.puts "# Database schema dumped on #{Time.now}"
          file.puts
          file.puts 'Sequel.migration do'
          file.puts '  up do'

          # Get all tables
          DB.tables.each do |table|
            next if table == :schema_migrations

            file.puts "    create_table :#{table} do"

            # Get table schema
            schema = DB.schema(table)
            schema.each do |column_name, column_info|
              column_type = column_info[:type]
              options = []

              options << 'null: false' unless column_info[:allow_null]
              options << 'primary_key: true' if column_info[:primary_key]
              options << "default: #{column_info[:default].inspect}" if column_info[:default]

              options_str = options.any? ? ", #{options.join(', ')}" : ''
              file.puts "      #{column_type} :#{column_name}#{options_str}"
            end

            # Get indexes
            indexes = DB.indexes(table)
            indexes.each do |_index_name, index_info|
              next if index_info[:unique] && index_info[:columns].length == 1 &&
                      schema.find { |col| col[0] == index_info[:columns][0] }&.dig(1, :primary_key)

              columns = index_info[:columns].map(&:inspect).join(', ')
              unique_str = index_info[:unique] ? ', unique: true' : ''
              file.puts "      index [#{columns}]#{unique_str}"
            end

            file.puts '    end'
            file.puts
          end

          file.puts '  end'
          file.puts 'end'
        end

        puts "Schema dumped to #{schema_file}"
      rescue StandardError => e
        puts "Error dumping schema: #{e.message}"
        exit 1
      end
    end

    desc 'Load the database schema'
    task :load do
      ensure_db_connection

      schema_file = File.expand_path('db/schema.rb', __dir__)

      if File.exist?(schema_file)
        begin
          # Drop all tables first
          DB.tables.each do |table|
            DB.drop_table(table, cascade: true) if DB.table_exists?(table)
          end

          # Load the schema
          load schema_file
          puts "Schema loaded from #{schema_file}"
        rescue StandardError => e
          puts "Error loading schema: #{e.message}"
          exit 1
        end
      else
        puts "Schema file '#{schema_file}' does not exist. Run 'rake db:schema:dump' first."
      end
    end

    desc 'Merge migrations into schema and remove them'
    task :merge do
      ensure_db_connection

      # First dump the current schema
      Rake::Task['db:schema:dump'].invoke

      # Remove migration files (keeping the directory)
      if Dir.exist?(MIGRATION_DIR)
        migration_files = Dir[File.join(MIGRATION_DIR, '*.rb')]
        migration_files.each do |file|
          File.delete(file)
          puts "Removed migration: #{File.basename(file)}"
        end

        # Clear schema_migrations table if it exists
        if DB.table_exists?(:schema_migrations)
          DB[:schema_migrations].delete
          puts 'Cleared schema_migrations table'
        end

        puts '✅ Migrations merged into schema and removed'
      else
        puts 'No migrations directory found'
      end
    end
  end
end

# Add a schema task that rebuilds schema.json (following Pliny convention)
desc 'Rebuild schema.json'
task :schema do
  ensure_db_connection

  schema_json_file = File.expand_path('schema/schema.json', __dir__)

  # Ensure schema directory exists
  FileUtils.mkdir_p(File.dirname(schema_json_file))

  begin
    # Generate a basic JSON schema representation
    schema_data = {
      '$schema' => 'http://json-schema.org/draft-04/schema#',
      'type' => 'object',
      'definitions' => {},
      'properties' => {},
      'generated_at' => Time.now.iso8601
    }

    # Add table definitions
    DB.tables.each do |table|
      next if table == :schema_migrations

      table_schema = {
        'type' => 'object',
        'properties' => {}
      }

      DB.schema(table).each do |column_name, column_info|
        column_type = case column_info[:type]
                      when :string, :text then 'string'
                      when :integer then 'integer'
                      when :boolean then 'boolean'
                      when :datetime, :timestamp then 'string'
                      when :uuid then 'string'
                      else 'string'
                      end

        table_schema['properties'][column_name.to_s] = {
          'type' => column_type
        }

        if %i[datetime timestamp].include?(column_info[:type])
          table_schema['properties'][column_name.to_s]['format'] = 'date-time'
        elsif column_info[:type] == :uuid
          table_schema['properties'][column_name.to_s]['format'] = 'uuid'
        end
      end

      schema_data['definitions'][table.to_s] = table_schema
    end

    # Write schema.json
    File.open(schema_json_file, 'w') do |file|
      file.puts JSON.pretty_generate(schema_data)
    end

    puts "Schema JSON rebuilt at #{schema_json_file}"
  rescue StandardError => e
    puts "Error rebuilding schema JSON: #{e.message}"
    exit 1
  end
end

# Default task
task default: :spec

# Add spec task if RSpec is available
begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  task :spec do
    puts 'RSpec is not available. Install it with: gem install rspec'
  end
end
