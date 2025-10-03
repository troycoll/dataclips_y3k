# frozen_string_literal: true

require_relative 'base_mediator'

# Mediator for deleting dataclip records
class DeleteDataclipMediator < BaseMediator
  def initialize(slug, params = {})
    super(params)
    @slug = slug&.to_s&.strip
  end

  def call
    validate_params
    return self unless success?

    delete_dataclip_record
    self
  end

  attr_reader :deleted_dataclip

  private

  attr_reader :slug

  def validate_params
    validate_presence(:slug, 'Slug is required') unless slug && !slug.empty?
    validate_dataclip_exists if slug && !slug.empty?
  end

  def validate_dataclip_exists
    @existing_dataclip = DB[:dataclips].where(slug: slug).first
    add_error('Dataclip not found') unless @existing_dataclip
  end

  def delete_dataclip_record
    # Store the dataclip before deletion for reference
    dataclip_to_delete = @existing_dataclip.dup

    handle_database_operation do
      DB[:dataclips].where(slug: slug).delete
      # Only set deleted_dataclip if delete was successful
      @deleted_dataclip = dataclip_to_delete

      # Invalidate cache when dataclip is deleted
      invalidate_dataclip_cache_if_enabled(slug)
    end
  end

  def invalidate_dataclip_cache_if_enabled(slug)
    return unless defined?(ClipWorker)

    ClipWorker.invalidate_cache(slug)
  rescue StandardError => e
    # Log but don't fail the delete operation due to cache issues
    unless ENV['RACK_ENV'] == 'test'
      puts "[DeleteDataclipMediator] Warning: Failed to invalidate cache for #{slug}: #{e.message}"
    end
  end
end
