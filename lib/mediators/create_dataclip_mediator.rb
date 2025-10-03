# frozen_string_literal: true

require_relative 'base_mediator'

# Mediator for creating dataclip records
class CreateDataclipMediator < BaseMediator
  def initialize(params = {})
    super
    @slug = generate_slug # Auto-generate 16-character alphanumeric slug
    @title = params[:title]&.to_s&.strip
    @description = params[:description]&.to_s&.strip
    @description = nil if @description&.empty?
    @sql_query = params[:sql_query]&.to_s&.strip
    @created_by = params[:created_by]&.to_s&.strip
    @created_by = nil if @created_by&.empty?
  end

  def call
    validate_params
    return self unless success?

    create_dataclip_record
    self
  end

  attr_reader :dataclip

  private

  attr_reader :slug, :title, :description, :sql_query, :created_by

  def validate_params
    validate_presence(:title, 'Title is required')
    validate_presence(:sql_query, 'SQL query is required')

    add_error('Title must be 255 characters or less') if title && title.length > 255

    add_error('SQL query must be 10,000 characters or less') if sql_query && sql_query.length > 10_000
  end

  def create_dataclip_record
    handle_database_operation do
      @dataclip = DB[:dataclips].insert(
        slug: slug,
        title: title,
        description: description,
        sql_query: sql_query,
        created_by: created_by,
        created_at: Time.now,
        updated_at: Time.now
      )
    end
  end
end
