# frozen_string_literal: true

require_relative 'base_mediator'

# Mediator for updating dataclip records
class UpdateDataclipMediator < BaseMediator
  def initialize(slug, params = {})
    super(params)
    @slug = slug
    @title = params[:title]&.to_s&.strip
    @description = params[:description]&.to_s&.strip
    @sql_query = params[:sql_query]&.to_s&.strip
    @created_by = params[:created_by]&.to_s&.strip
  end

  def call
    validate_params
    return self unless success?

    update_dataclip_record
    self
  end

  attr_reader :dataclip

  private

  attr_reader :slug, :title, :description, :sql_query, :created_by

  def validate_params
    validate_presence(:title, 'Title is required') if title
    validate_presence(:sql_query, 'SQL query is required') if sql_query

    add_error('Title must be 255 characters or less') if title && title.length > 255

    add_error('SQL query must be 10,000 characters or less') if sql_query && sql_query.length > 10_000

    validate_dataclip_exists
  end

  def validate_dataclip_exists
    @existing_dataclip = DB[:dataclips].where(slug: slug).first
    add_error('Dataclip not found') unless @existing_dataclip
  end

  def update_dataclip_record
    updates = { updated_at: Time.now }

    updates[:title] = title if title && !title.empty?
    updates[:description] = description.empty? ? nil : description if description
    updates[:sql_query] = sql_query if sql_query && !sql_query.empty?
    updates[:created_by] = created_by.empty? ? nil : created_by if created_by

    handle_database_operation do
      DB[:dataclips].where(slug: slug).update(updates)
      @dataclip = DB[:dataclips].where(slug: slug).first
    end
  end
end
