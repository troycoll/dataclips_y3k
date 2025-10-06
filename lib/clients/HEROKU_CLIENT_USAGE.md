# Heroku API Client Usage Guide

## Overview

The `HerokuClient` class provides a Ruby interface for interacting with the Heroku Platform API. It's built on top of the `platform-api` gem and includes comprehensive error handling and convenience methods for working with Heroku addons.

## Configuration

### Environment Variables

Add the following environment variable to your `.env` file:

```bash
# Required: Your Heroku API token
# Get it from: https://dashboard.heroku.com/account
HEROKU_API_TOKEN=your-heroku-api-token-here
```

**Note:** `HEROKU_APP_NAME` is automatically provided by Heroku when your app is running on the platform and does not need to be set manually. For local development, you can optionally set it in your `.env` file if you want to test against a specific Heroku app.

## Basic Usage

### Initialize the Client

```ruby
require_relative 'lib/clients/heroku'

# Initialize with environment variable (recommended)
client = HerokuClient.new

# Or initialize with explicit token
client = HerokuClient.new(api_token: 'your-token-here')
```

### Fetch All Addons

```ruby
# Get all addons for an app
addons = client.fetch_addons('your-app-name')

# Response example:
# [
#   {
#     "id" => "12345678-1234-1234-1234-123456789abc",
#     "name" => "postgresql-vertical-12345",
#     "addon_service" => {"name" => "heroku-postgresql"},
#     "plan" => {"name" => "heroku-postgresql:standard-0"},
#     "created_at" => "2024-01-01T00:00:00Z",
#     "updated_at" => "2024-01-01T00:00:00Z"
#   },
#   ...
# ]

addons.each do |addon|
  puts "Addon: #{addon['name']} (#{addon.dig('addon_service', 'name')})"
end
```

### Fetch PostgreSQL Addons Only

```ruby
# Get only PostgreSQL database addons
postgres_addons = client.fetch_postgres_addons('your-app-name')

postgres_addons.each do |addon|
  puts "Database: #{addon['name']}"
  puts "  ID: #{addon['id']}"
  puts "  Plan: #{addon.dig('plan', 'name')}"
end
```

### Fetch a Specific Addon

```ruby
# By addon ID
addon = client.fetch_addon('your-app-name', '12345678-1234-1234-1234-123456789abc')

# Or by addon name
addon = client.fetch_addon('your-app-name', 'postgresql-vertical-12345')

puts "Addon Name: #{addon['name']}"
puts "Service: #{addon.dig('addon_service', 'name')}"
```

### Check if an Addon is PostgreSQL

```ruby
addon = client.fetch_addon('your-app-name', 'postgresql-vertical-12345')

if client.postgres_addon?(addon)
  puts "This is a PostgreSQL addon"
else
  puts "This is not a PostgreSQL addon"
end
```

### Fetch Addon Configuration

```ruby
# Get config vars (environment variables) related to an addon
config = client.fetch_addon_config('your-app-name', 'postgresql-vertical-12345')

# Response example:
# {
#   "POSTGRESQL_VERTICAL_12345_URL" => "postgres://user:pass@host:5432/db"
# }

config.each do |key, value|
  puts "#{key}: #{value}"
end
```

### Health Check

```ruby
# Verify API connectivity
begin
  client.health_check
  puts "✓ Heroku API is accessible"
rescue HerokuClient::HerokuAPIError => e
  puts "✗ Heroku API health check failed: #{e.message}"
end
```

### Get Account Information

```ruby
account = client.account_info
puts "Account Email: #{account['email']}"
puts "Account ID: #{account['id']}"
```

## Error Handling

The client raises two types of custom errors:

### ConfigurationError

Raised when the API token is missing or invalid during initialization:

```ruby
begin
  client = HerokuClient.new
rescue HerokuClient::ConfigurationError => e
  puts "Configuration error: #{e.message}"
  # Output: "HEROKU_API_TOKEN environment variable is required"
end
```

### HerokuAPIError

Raised for all API-related errors:

```ruby
begin
  addons = client.fetch_addons('non-existent-app')
rescue HerokuClient::HerokuAPIError => e
  puts "API error: #{e.message}"
  # Output: "App 'non-existent-app' not found: ..."
end
```

## Integration Example: Associating Dataclips with Addons

Here's how you might integrate the Heroku client with the dataclips system:

```ruby
# In a controller or mediator
require_relative 'lib/clients/heroku'

def list_available_databases
  heroku = HerokuClient.new
  app_name = ENV['HEROKU_APP_NAME']
  
  # Get all PostgreSQL databases
  postgres_addons = heroku.fetch_postgres_addons(app_name)
  
  # Format for display in a form
  postgres_addons.map do |addon|
    {
      id: addon['id'],
      name: addon['name'],
      plan: addon.dig('plan', 'name'),
      display_name: "#{addon['name']} (#{addon.dig('plan', 'name')})"
    }
  end
rescue HerokuClient::HerokuAPIError => e
  Rails.logger.error "Failed to fetch Heroku addons: #{e.message}"
  []
end

def create_dataclip_with_addon(params)
  # Create dataclip with associated addon_id
  dataclip = DB[:dataclips].insert(
    slug: params[:slug],
    title: params[:title],
    sql_query: params[:sql_query],
    addon_id: params[:addon_id],  # From Heroku API
    addon_name: params[:addon_name],
    created_at: Time.now
  )
end
```

## Rate Limiting

The `platform-api` gem (v3.0.0+) includes automatic rate throttling:

- The client automatically retries requests when rate-limited
- Auto-tunes sleep intervals to avoid future rate limits
- Uses exponential backoff strategy by default
- Logs throttling events to STDOUT

You typically don't need to worry about rate limiting as it's handled automatically.

## Testing

The client is fully tested with RSpec. Run tests with:

```bash
bundle exec rspec spec/lib/clients/heroku_spec.rb
```

All API calls are mocked in tests, so no actual API requests are made during testing.

## API Documentation

For more information about the Heroku Platform API:
- [Heroku Platform API Documentation](https://devcenter.heroku.com/articles/platform-api-reference)
- [platform-api Gem Documentation](https://github.com/heroku/platform-api)

## Database Migration

To add addon association to dataclips, run the migration:

```bash
bundle exec rake db:migrate
```

This will add `addon_id` and `addon_name` columns to the `dataclips` table.

## Deployment on Heroku

When running on Heroku, `HEROKU_APP_NAME` is automatically available as an environment variable. You only need to set your API token:

```bash
heroku config:set HEROKU_API_TOKEN=your-token-here
```

Then the client will automatically use the correct app name:

```ruby
client = HerokuClient.new
addons = client.fetch_postgres_addons(ENV['HEROKU_APP_NAME'])
```

## Local Development

For local development, you can optionally set `HEROKU_APP_NAME` in your `.env` file if you want to test against a specific Heroku app:

```bash
# .env (local development only)
HEROKU_API_TOKEN=your-token-here
HEROKU_APP_NAME=your-app-name  # Optional for local testing
```

