# frozen_string_literal: true

module Config
  class << self
    def setup!
      load_environment
      setup_databases
      puts '✅ Application configuration loaded successfully!'
    end

    def environment
      ENV.fetch('RACK_ENV', 'development')
    end

    def development?
      environment == 'development'
    end

    def production?
      environment == 'production'
    end

    def test?
      environment == 'test'
    end

    def database_url
      ENV['DATABASE_URL'] || raise('DATABASE_URL environment variable is required')
    end

    def max_connections
      ENV.fetch('DB_MAX_CONNECTIONS', 10).to_i
    end

    def log_level
      ENV.fetch('LOG_LEVEL', 'info')
    end

    private

    def load_environment
      # Load .env file if it exists
      env_file = File.expand_path('../.env', __dir__)
      if File.exist?(env_file)
        require 'dotenv'
        Dotenv.load(env_file)
        puts "🔧 Loading configuration for #{environment} environment from .env file..."
      else
        puts "🔧 Loading configuration for #{environment} environment (no .env file found)..."
      end
    end

    def setup_databases
      require_relative 'initializers/postgresql'
      require_relative 'initializers/sqlite'

      PostgreSQLInitializer.setup!
      SQLiteInitializer.setup!
    end
  end
end
