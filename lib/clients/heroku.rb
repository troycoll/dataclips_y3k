# frozen_string_literal: true

require 'platform-api'

# Heroku API Client
# Provides methods for interacting with the Heroku Platform API
# Primary use: Fetching addon information to associate dataclips with specific database addons
class HerokuClient
  class HerokuAPIError < StandardError; end
  class ConfigurationError < StandardError; end

  attr_reader :client

  # Initialize the Heroku API client
  # @param api_token [String] Heroku API token (defaults to ENV['HEROKU_API_TOKEN'])
  # @raise [ConfigurationError] if API token is missing
  def initialize(api_token: nil)
    @api_token = api_token || ENV['HEROKU_API_TOKEN']

    raise ConfigurationError, 'HEROKU_API_TOKEN environment variable is required' if @api_token.nil? || @api_token.empty?

    @client = PlatformAPI.connect_oauth(@api_token)
  end

  # Fetch all addons attached to a Heroku app
  # @param app_name [String] Name of the Heroku app
  # @return [Array<Hash>] Array of addon hashes with keys: id, name, addon_service (name/plan), created_at, updated_at
  # @raise [HerokuAPIError] if the API request fails
  #
  # Example response:
  # [
  #   {
  #     "id" => "12345678-1234-1234-1234-123456789abc",
  #     "name" => "postgresql-vertical-12345",
  #     "addon_service" => {"name" => "heroku-postgresql"},
  #     "plan" => {"name" => "heroku-postgresql:standard-0"},
  #     "created_at" => "2024-01-01T00:00:00Z",
  #     "updated_at" => "2024-01-01T00:00:00Z"
  #   }
  # ]
  def fetch_addons(app_name)
    validate_app_name!(app_name)

    @client.addon.list(app_name)
  rescue ArgumentError => e
    raise e
  rescue Excon::Error::NotFound => e
    raise HerokuAPIError, "App '#{app_name}' not found: #{e.message}"
  rescue Excon::Error => e
    raise HerokuAPIError, "Failed to fetch addons for app '#{app_name}': #{e.message}"
  rescue StandardError => e
    raise HerokuAPIError, "Unexpected error fetching addons: #{e.message}"
  end

  # Fetch a specific addon by ID or name
  # @param app_name [String] Name of the Heroku app
  # @param addon_id_or_name [String] Addon UUID or addon name
  # @return [Hash] Addon details
  # @raise [HerokuAPIError] if the API request fails
  def fetch_addon(app_name, addon_id_or_name)
    validate_app_name!(app_name)
    validate_addon_identifier!(addon_id_or_name)

    @client.addon.info(app_name, addon_id_or_name)
  rescue ArgumentError => e
    raise e
  rescue Excon::Error::NotFound => e
    raise HerokuAPIError, "Addon '#{addon_id_or_name}' not found for app '#{app_name}': #{e.message}"
  rescue Excon::Error => e
    raise HerokuAPIError, "Failed to fetch addon '#{addon_id_or_name}': #{e.message}"
  rescue StandardError => e
    raise HerokuAPIError, "Unexpected error fetching addon: #{e.message}"
  end

  # Fetch only PostgreSQL addons from a Heroku app
  # @param app_name [String] Name of the Heroku app
  # @return [Array<Hash>] Array of PostgreSQL addon hashes
  def fetch_postgres_addons(app_name)
    addons = fetch_addons(app_name)
    addons.select { |addon| postgres_addon?(addon) }
  end

  # Check if an addon is a PostgreSQL addon
  # @param addon [Hash] Addon hash from the API
  # @return [Boolean] true if the addon is a PostgreSQL addon
  def postgres_addon?(addon)
    return false unless addon['addon_service']

    service_name = addon.dig('addon_service', 'name')
    return false if service_name.nil?

    service_name.downcase.include?('postgres')
  end

  # Get addon connection information (config vars)
  # @param app_name [String] Name of the Heroku app
  # @param addon_id_or_name [String] Addon UUID or addon name
  # @return [Hash] Addon config vars (e.g., DATABASE_URL)
  # @raise [HerokuAPIError] if the API request fails
  def fetch_addon_config(app_name, addon_id_or_name)
    addon = fetch_addon(app_name, addon_id_or_name)

    # Get config vars for the app
    config_vars = @client.config_var.info_for_app(app_name)

    # Filter to only config vars related to this addon
    # Addon config vars typically include the addon name
    addon_name = addon['name']
    config_vars.select { |key, _value| key.upcase.include?(addon_name.upcase.gsub('-', '_')) }
  rescue Excon::Error => e
    raise HerokuAPIError, "Failed to fetch addon config: #{e.message}"
  rescue StandardError => e
    raise HerokuAPIError, "Unexpected error fetching addon config: #{e.message}"
  end

  # Health check to verify API connectivity
  # @return [Boolean] true if connection is successful
  # @raise [HerokuAPIError] if connection fails
  def health_check
    # Try to fetch account info as a simple health check
    @client.account.info
    true
  rescue Excon::Error => e
    raise HerokuAPIError, "Heroku API health check failed: #{e.message}"
  rescue StandardError => e
    raise HerokuAPIError, "Unexpected error during health check: #{e.message}"
  end

  # Get the current account information
  # @return [Hash] Account details (email, id, etc.)
  def account_info
    @client.account.info
  rescue Excon::Error => e
    raise HerokuAPIError, "Failed to fetch account info: #{e.message}"
  rescue StandardError => e
    raise HerokuAPIError, "Unexpected error fetching account info: #{e.message}"
  end

  private

  def validate_app_name!(app_name)
    raise ArgumentError, 'app_name cannot be nil or empty' if app_name.nil? || app_name.to_s.strip.empty?
  end

  def validate_addon_identifier!(identifier)
    raise ArgumentError, 'addon identifier cannot be nil or empty' if identifier.nil? || identifier.to_s.strip.empty?
  end
end
