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
    super({})
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
    log_error(e)
    self
  rescue HerokuClient::HerokuAPIError => e
    add_error("Failed to sync addons from Heroku: #{e.message}")
    log_error(e)
    self
  rescue StandardError => e
    add_error("Unexpected error syncing addons: #{e.message}")
    log_error(e)
    self
  end

  attr_reader :synced_count, :skipped_count

  private

  def validate_configuration!
    if @app_name.nil? || @app_name.strip.empty?
      raise HerokuClient::ConfigurationError, 'HEROKU_APP_NAME environment variable is required'
    end
    puts "[DEBUG] SyncAddonsMediator: Configuration validated. App name: #{@app_name}"
  end

  def fetch_and_sync_addons
    puts "[DEBUG] SyncAddonsMediator: Creating HerokuClient..."
    heroku_client = HerokuClient.new

    puts "[DEBUG] SyncAddonsMediator: Fetching addons for app: #{@app_name}"
    addons = heroku_client.fetch_addons(@app_name)

    puts "[DEBUG] SyncAddonsMediator: Fetched #{addons&.length || 0} addons"
    return if addons.nil? || addons.empty?

    addons.each_with_index do |addon, index|
      puts "[DEBUG] SyncAddonsMediator: Processing addon #{index + 1}/#{addons.length}: #{addon['name']}"
      sync_addon(addon)
    end
  end

  def sync_addon(addon)
    addon_uuid = addon['id']
    addon_name = addon['name']

    return unless addon_uuid && addon_name

    puts "[DEBUG] SyncAddonsMediator: Upserting addon - UUID: #{addon_uuid}, Name: #{addon_name}"
    # Use upsert to insert or update the addon
    upsert_addon_record(addon_uuid, addon_name)
    @synced_count += 1
    puts "[DEBUG] SyncAddonsMediator: Successfully synced addon: #{addon_name}"
  rescue StandardError => e
    add_error("Failed to sync addon '#{addon_name}': #{e.message}")
    log_error(e, context: "sync_addon for #{addon_name}")
    @skipped_count += 1
  end

  def upsert_addon_record(uuid, name)
    puts "[DEBUG] SyncAddonsMediator#upsert_addon_record: Starting upsert for UUID: #{uuid}, Name: #{name}"

    puts "[DEBUG] SyncAddonsMediator#upsert_addon_record: Checking if addon exists..."
    existing = DB[:addons].where(uuid: uuid).first
    puts "[DEBUG] SyncAddonsMediator#upsert_addon_record: Existing addon: #{existing ? 'found' : 'not found'}"

    if existing
      puts "[DEBUG] SyncAddonsMediator#upsert_addon_record: Updating existing addon..."
      DB[:addons].where(uuid: uuid).update(
        name: name,
        updated_at: Time.now
      )
      puts "[DEBUG] SyncAddonsMediator#upsert_addon_record: Update complete"
    else
      puts "[DEBUG] SyncAddonsMediator#upsert_addon_record: Inserting new addon..."
      DB[:addons].insert(
        uuid: uuid,
        name: name,
        created_at: Time.now,
        updated_at: Time.now
      )
      puts "[DEBUG] SyncAddonsMediator#upsert_addon_record: Insert complete"
    end
  rescue StandardError => e
    puts "[ERROR] SyncAddonsMediator#upsert_addon_record failed: #{e.class}: #{e.message}"
    puts "[ERROR] Backtrace:\n#{e.backtrace.join("\n")}"
    raise
  end

  def log_error(error, context: nil)
    puts "[ERROR] SyncAddonsMediator: #{context ? "#{context} - " : ''}#{error.class}: #{error.message}"
    puts "[ERROR] Backtrace:"
    puts error.backtrace.join("\n")
  end
end
