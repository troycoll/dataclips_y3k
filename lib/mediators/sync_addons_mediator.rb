# frozen_string_literal: true

require_relative '../clients/heroku'

# SyncAddonsMediator handles syncing Heroku addons to the local database
# This mediator fetches addons from the Heroku API and updates the addons table
class SyncAddonsMediator < BaseMediator
  # Sync Heroku addons to the local database
  # @param app_name [String] The Heroku app name (optional, defaults to ENV['HEROKU_APP_NAME'])
  # @return [Result] The result object with success status and any errors
  #
  # Example usage:
  #   result = SyncAddonsMediator.call
  #   if result.success?
  #     puts "Synced #{result.synced_count} addons"
  #   end
  def self.call(app_name: nil)
    new(app_name: app_name).call
  end

  def initialize(app_name: nil)
    super()
    @app_name = app_name || ENV['HEROKU_APP_NAME']
    @synced_count = 0
    @skipped_count = 0
  end

  def call
    validate_configuration!
    fetch_and_sync_addons
    self
  rescue HerokuClient::ConfigurationError => e
    # Silently skip if Heroku is not configured (development/local environments)
    add_error("Heroku API not configured: #{e.message}")
    self
  rescue HerokuClient::HerokuAPIError => e
    add_error("Failed to sync addons from Heroku: #{e.message}")
    self
  rescue StandardError => e
    add_error("Unexpected error syncing addons: #{e.message}")
    self
  end

  attr_reader :synced_count, :skipped_count

  private

  def validate_configuration!
    if @app_name.nil? || @app_name.strip.empty?
      raise HerokuClient::ConfigurationError, 'HEROKU_APP_NAME environment variable is required'
    end
  end

  def fetch_and_sync_addons
    heroku_client = HerokuClient.new
    addons = heroku_client.fetch_addons(@app_name)

    return if addons.nil? || addons.empty?

    addons.each do |addon|
      sync_addon(addon)
    end
  end

  def sync_addon(addon)
    addon_uuid = addon['id']
    addon_name = addon['name']

    return unless addon_uuid && addon_name

    # Use upsert to insert or update the addon
    upsert_addon(addon_uuid, addon_name)
    @synced_count += 1
  rescue StandardError => e
    add_error("Failed to sync addon '#{addon_name}': #{e.message}")
    @skipped_count += 1
  end
end
