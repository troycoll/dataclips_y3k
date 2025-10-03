# frozen_string_literal: true

require 'rspec'
require 'rack/test'
require 'sequel'
require 'sequel/extensions/migration'
require 'uri'
require 'stringio'

# Load test environment variables
if File.exist?('.env.test')
  File.readlines('.env.test').each do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')

    key, value = line.split('=', 2)
    ENV[key] = value if key && value
  end
end

# Set test environment
ENV['RACK_ENV'] = 'test'

# Set default test database URL if not provided
ENV['DATABASE_URL'] ||= 'postgres://localhost/dataclips_test'

# Setup test database before requiring the application
def setup_test_database
  database_url = ENV['DATABASE_URL']

  # Parse database URL to get database name
  uri = URI.parse(database_url)
  database_name = uri.path[1..-1] # Remove leading slash

  # Connect to PostgreSQL server (without database name) to create database if needed
  server_url = "#{uri.scheme}://#{uri.userinfo ? "#{uri.userinfo}@" : ''}#{uri.host}#{uri.port ? ":#{uri.port}" : ''}/postgres"

  begin
    # Connect to server and create database if it doesn't exist
    server_db = Sequel.connect(server_url, logger: nil)

    # Check if database exists
    db_exists = server_db.fetch('SELECT 1 FROM pg_database WHERE datname = ?', database_name).first

    unless db_exists
      puts "Creating test database: #{database_name}"
      server_db.run("CREATE DATABASE #{database_name}")
    end

    server_db.disconnect
  rescue Sequel::DatabaseError => e
    # Database might already exist or we might not have permissions
    puts "Note: #{e.message}" if ENV['DEBUG']
  end

  # Connect to the test database
  test_db = Sequel.connect(database_url, logger: nil)
  Object.const_set(:DB, test_db) unless defined?(DB)

  # Enable UUID extension
  begin
    test_db.run('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
  rescue Sequel::DatabaseError
    # Extension might already exist or not be available
  end

  # Run migrations (create tables if they don't exist)
  migrate_test_database(test_db)

  # Seed test data
  seed_test_database(test_db)
end

def migrate_test_database(db)
  # Run migrations from db/migrate directory
  migrations_dir = File.expand_path('../db/migrate', __dir__)

  if Dir.exist?(migrations_dir)
    puts 'Running database migrations for testing'

    # Use Sequel's migration system to run all migrations
    Sequel::Migrator.run(db, migrations_dir)

    puts 'Database migrations completed'
  else
    puts 'No migrations directory found, skipping migrations'
  end
end

def seed_test_database(db)
  # Load and run seeds for test environment
  seeds_file = File.expand_path('../db/seeds.rb', __dir__)

  if File.exist?(seeds_file)
    puts 'Running database seeds for testing'

    # Clear existing test seed data (idempotent)
    db[:dataclips].where(created_by: %w[admin finance_team test_seed]).delete

    # Ensure required classes are loaded before running seeds
    begin
      # Load Config class if not already loaded
      require_relative '../config/config' unless defined?(Config)

      # Load CreateDataclipMediator if not already loaded
      require_relative '../lib/mediators/create_dataclip_mediator' unless defined?(CreateDataclipMediator)

      # Setup helper methods that seeds.rb expects (from PostgreSQL initializer)
      unless Object.respond_to?(:get_all_dataclips)
        Object.class_eval do
          def get_all_dataclips
            DB[:dataclips].order(:created_at).all
          end
        end
      end
    rescue LoadError => e
      puts "Error loading required classes for seeding: #{e.message}"
      return
    end

    # Temporarily override Config methods for test environment
    original_development = Config.method(:development?) if Config.respond_to?(:development?)
    original_test = Config.method(:test?) if Config.respond_to?(:test?)

    # Override Config methods to make seeds think we're in development mode
    # so it will clear and recreate the sample data
    Config.define_singleton_method(:development?) { true }
    Config.define_singleton_method(:test?) { true }

    begin
      # Capture output to avoid cluttering test output
      original_stdout = $stdout
      $stdout = StringIO.new unless ENV['DEBUG']

      # Load and execute the seeds file
      load seeds_file
    rescue StandardError => e
      puts "Error running seeds: #{e.message}"
      puts e.backtrace if ENV['DEBUG']
    ensure
      # Restore original output
      $stdout = original_stdout unless ENV['DEBUG']

      # Restore original Config methods
      Config.define_singleton_method(:development?, original_development) if original_development
      Config.define_singleton_method(:test?, original_test) if original_test
    end

    # Count seeded records
    seeded_count = db[:dataclips].where(created_by: %w[admin finance_team]).count
    puts "Seeded #{seeded_count} test dataclips from seeds.rb"

  else
    puts 'No seeds.rb file found, skipping database seeding'
  end
end

# Setup test database
setup_test_database

# Require the application after database setup
require_relative '../lib/app'

# Load shared examples
Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

# Configure RSpec
RSpec.configure do |config|
  # Include Rack::Test methods for testing Sinatra apps
  config.include Rack::Test::Methods

  # Use expect syntax only
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  # Use expect syntax for mocks
  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.verify_partial_doubles = true
  end

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option
  Kernel.srand config.seed

  # Print the slowest examples and example groups
  config.profile_examples = 10

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Clean up test data between test runs
  config.before(:each) do
    # Clean up any test data that wasn't created by seeds (admin, finance_team)
    DB[:dataclips].where(Sequel.~(created_by: %w[admin finance_team])).delete if defined?(DB)
  end
end

# Helper method for Sinatra app testing
def app
  Sinatra::Application
end
