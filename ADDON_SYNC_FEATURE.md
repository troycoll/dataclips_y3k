# Addon Sync Feature

## Overview
This feature automatically syncs Heroku addons to the local database whenever a user visits the `/dataclips/list` or `/dataclips/:slug/edit` pages.

## Implementation

### 1. SyncAddonsMediator (`lib/mediators/sync_addons_mediator.rb`)
- **Purpose**: Fetches addons from the Heroku Platform API and syncs them to the local `addons` table
- **Key Features**:
  - Uses `HerokuClient` to fetch addon information
  - Upserts addons into the database (inserts new, updates existing)
  - Gracefully handles configuration errors (e.g., when Heroku credentials are not set)
  - Returns sync statistics (`synced_count`, `skipped_count`)
  - Inherits from `BaseMediator` for consistent error handling

### 2. Database Helper Methods
The `SyncAddonsMediator` contains its own addon management method:
- `upsert_addon_record(uuid, name)` - Insert or update an addon (private method)

The `config/initializers/postgresql.rb` also provides global helper methods:
- `get_addon(uuid)` - Retrieve a single addon by UUID
- `get_all_addons` - Get all addons from the database
- `delete_addon(uuid)` - Remove an addon by UUID

### 3. Application Integration (`lib/app.rb`)
- **Added Helper Method**: `sync_heroku_addons`
  - Calls `SyncAddonsMediator.call`
  - Silently handles failures (e.g., missing configuration)
  - Logs sync results in debug mode
  
- **Updated Routes**:
  - `GET /dataclips/list` - Now syncs addons before rendering
  - `GET /dataclips/:slug/edit` - Now syncs addons before rendering

## Environment Variables
- `HEROKU_API_TOKEN` - Your Heroku API token (required)
- `HEROKU_APP_NAME` - The Heroku app name to sync addons from (automatically set by Heroku)

## Behavior

### Success Case
1. User visits `/dataclips/list` or `/dataclips/:slug/edit`
2. App calls Heroku API to fetch all addons for the configured app
3. Addons are synced to the `addons` table (upserted)
4. Page renders normally

### Configuration Missing Case
1. User visits `/dataclips/list` or `/dataclips/:slug/edit`
2. `HEROKU_API_TOKEN` or `HEROKU_APP_NAME` is not configured
3. Sync fails silently (logged in debug mode)
4. Page renders normally without errors shown to user

### API Error Case
1. User visits `/dataclips/list` or `/dataclips/:slug/edit`
2. Heroku API returns an error
3. Sync fails silently (logged in debug mode)
4. Page renders normally without errors shown to user

## Testing
- **Unit Tests**: `spec/lib/mediators/sync_addons_mediator_spec.rb` (12 examples)
  - Tests successful sync
  - Tests configuration errors
  - Tests API errors
  - Tests addon updates
  - Tests malformed data handling

- **Integration Tests**: `spec/lib/app_spec.rb`
  - Tests that sync is called on list and edit pages
  - Tests that failures don't break page rendering

All 284 tests pass successfully.

## Database Schema
The `addons` table (created by migration `003_create_addons.rb`):
```sql
CREATE TABLE addons (
  id SERIAL PRIMARY KEY,
  uuid UUID NOT NULL UNIQUE,
  name VARCHAR NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Usage in Development
1. Set `HEROKU_API_TOKEN` in your `.env` file
2. Set `HEROKU_APP_NAME` in your `.env` file (or let Heroku set it automatically)
3. Visit `/dataclips/list` or any edit page
4. Check the `addons` table to see synced addons

## Notes
- Sync happens on every page load (not cached)
- Failed syncs don't interrupt the user experience
- Only PostgreSQL addons are fetched, but all addons are stored
- The sync is idempotent - running it multiple times is safe

