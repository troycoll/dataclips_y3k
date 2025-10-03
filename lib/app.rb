# frozen_string_literal: true

require 'sinatra'
require_relative '../config/config'
require_relative 'mediators/create_dataclip_mediator'
require_relative 'mediators/update_dataclip_mediator'
require_relative 'mediators/delete_dataclip_mediator'
require_relative 'workers/clip_worker'
require_relative 'workers/schema_worker'

Config.setup!

set :views, File.expand_path('../views', __dir__)

enable :sessions

helpers do
  def flash_errors
    errors = session.delete(:errors)
    return '' unless errors && !errors.empty?

    error_list = errors.map { |error| "<li>#{error}</li>" }.join
    "<div class='alert alert-danger'><ul>#{error_list}</ul></div>"
  end

  def flash_success
    message = session.delete(:success)
    return '' unless message

    "<div class='alert alert-success'>#{message}</div>"
  end

  def flash_messages
    flash_errors + flash_success
  end
end

get '/' do
  redirect '/dataclips/list'
end

get '/dataclips/list' do
  @dataclips = get_all_dataclips
  erb :list
end

post '/dataclips/create' do
  result = CreateDataclipMediator.call(params)

  if result.success?
    session[:success] = "Dataclip '#{params[:title]}' was successfully created."
    redirect '/dataclips/list'
  else
    session[:errors] = result.errors
    redirect '/dataclips/edit'
  end
end

get '/dataclips/:slug/edit' do
  @dataclip = get_dataclip(params[:slug])

  if @dataclip.nil?
    session[:errors] = ["Dataclip with slug '#{params[:slug]}' not found"]
    redirect '/dataclips/list'
  else
    erb :edit
  end
end

put '/dataclips/:slug/update' do
  result = UpdateDataclipMediator.call(params[:slug], params)

  if result.success?
    session[:success] = "Dataclip '#{result.dataclip[:title]}' was successfully updated."
    redirect "/dataclips/#{params[:slug]}"
  else
    session[:errors] = result.errors
    redirect "/dataclips/#{params[:slug]}/edit"
  end
end

delete '/dataclips/:slug/delete' do
  result = DeleteDataclipMediator.call(params[:slug])

  if result.success?
    session[:success] = "Dataclip '#{result.deleted_dataclip[:title]}' was successfully deleted."
  else
    session[:errors] = result.errors
  end

  redirect '/dataclips/list'
end

get '/dataclips/:slug' do
  @dataclip = get_dataclip(params[:slug])

  if @dataclip.nil?
    session[:errors] = ["Dataclip with slug '#{params[:slug]}' not found"]
    redirect '/dataclips/list'
  else
    erb :show
  end
end

# API endpoint for executing dataclips
post '/api/dataclips/:slug/execute' do
  content_type :json

  begin
    result = ClipWorker.execute_dataclip(params[:slug])
    result.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      errors: ["Failed to execute dataclip: #{e.message}"],
      data: [],
      columns: [],
      row_count: 0,
      execution_time: 0
    }.to_json
  end
end

# API endpoint for executing raw SQL (for testing in edit view)
post '/api/sql/execute' do
  content_type :json

  begin
    sql_query = params[:sql_query] || request.body.read
    if sql_query.is_a?(String) && sql_query.start_with?('{')
      # Handle JSON payload
      json_data = JSON.parse(sql_query)
      sql_query = json_data['sql_query']
    end

    result = ClipWorker.execute(sql_query)
    result.to_json
  rescue JSON::ParserError => e
    status 400
    {
      success: false,
      errors: ["Invalid JSON: #{e.message}"],
      data: [],
      columns: [],
      row_count: 0,
      execution_time: 0
    }.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      errors: ["Failed to execute SQL: #{e.message}"],
      data: [],
      columns: [],
      row_count: 0,
      execution_time: 0
    }.to_json
  end
end

# API endpoint for fetching database schema
get '/api/schema' do
  content_type :json

  begin
    result = SchemaWorker.fetch_schema
    result.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      schema: {},
      errors: ["Failed to fetch schema: #{e.message}"]
    }.to_json
  end
end

# API endpoint for cache statistics
get '/api/cache/stats' do
  content_type :json

  begin
    stats = ClipWorker.cache_stats
    {
      success: true,
      stats: stats
    }.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      stats: {},
      errors: ["Failed to fetch cache stats: #{e.message}"]
    }.to_json
  end
end

# API endpoint for cache cleanup (remove expired entries)
post '/api/cache/cleanup' do
  content_type :json

  begin
    cleared_count = ClipWorker.cleanup_cache
    {
      success: true,
      message: "Cleared #{cleared_count} expired cache entries",
      cleared_count: cleared_count
    }.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      errors: ["Failed to cleanup cache: #{e.message}"]
    }.to_json
  end
end

# API endpoint for invalidating cache for a specific dataclip
delete '/api/cache/dataclip/:slug' do
  content_type :json

  begin
    cleared_count = ClipWorker.invalidate_cache(params[:slug])
    {
      success: true,
      message: "Invalidated cache for dataclip '#{params[:slug]}'",
      cleared_count: cleared_count
    }.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      errors: ["Failed to invalidate cache: #{e.message}"]
    }.to_json
  end
end

# API endpoint for schema cache statistics
get '/api/cache/schema/stats' do
  content_type :json

  begin
    stats = SchemaWorker.cache_stats
    {
      success: true,
      stats: stats
    }.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      stats: {},
      errors: ["Failed to fetch schema cache stats: #{e.message}"]
    }.to_json
  end
end

# API endpoint for schema cache cleanup (remove expired entries)
post '/api/cache/schema/cleanup' do
  content_type :json

  begin
    cleared_count = SchemaWorker.cleanup_cache
    {
      success: true,
      message: "Cleared #{cleared_count} expired schema cache entries",
      cleared_count: cleared_count
    }.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      errors: ["Failed to cleanup schema cache: #{e.message}"]
    }.to_json
  end
end

# API endpoint for clearing all schema cache
delete '/api/cache/schema' do
  content_type :json

  begin
    cleared_count = SchemaWorker.clear_cache
    {
      success: true,
      message: "Cleared all schema cache entries",
      cleared_count: cleared_count
    }.to_json
  rescue StandardError => e
    status 500
    {
      success: false,
      errors: ["Failed to clear schema cache: #{e.message}"]
    }.to_json
  end
end
