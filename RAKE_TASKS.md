# Database Rake Tasks

This project includes comprehensive database management rake tasks based on the [Pliny framework](https://github.com/interagent/pliny) conventions with environment-specific behavior.

## Environment-Specific Behavior

The rake tasks automatically detect the environment using the `RACK_ENV` environment variable and behave differently:

### 🧪 Development & Test Environments
- **Database Creation**: Creates PostgreSQL database if it doesn't exist
- **Migrations**: Runs all migrations 
- **Seeding**: Populates database with sample data for testing

### 🚀 Production Environment  
- **Database Creation**: Skipped (assumes pre-existing database)
- **Migrations**: Only creates the `dataclips` table on existing database
- **Seeding**: Skipped (no sample data in production)

## Prerequisites

The Rakefile automatically loads environment variables from a `.env` file in the project root if it exists.

Set up your environment variables by copying the example file:

```bash
cp env.example .env
```

Edit `.env` and set your `DATABASE_URL` and `RACK_ENV`:

```bash
# Development
DATABASE_URL=postgres://username:password@localhost:5432/dataclips_y3k_development
RACK_ENV=development

# Production  
DATABASE_URL=postgres://user:pass@prod-host:5432/existing_production_db
RACK_ENV=production
```

**Note**: The `.env` file is automatically loaded by both the Rakefile and the application's Config module, so you don't need to manually source it.

## Available Tasks

View all available rake tasks:

```bash
rake -T
```

### Database Management

#### Create Database
```bash
rake db:create
```
Creates the database specified in `DATABASE_URL`.
- **Development/Test**: Creates database if it doesn't exist
- **Production**: Skipped (assumes database already exists)

#### Drop Database
```bash
rake db:drop
```
Drops the database (⚠️ **WARNING**: This permanently deletes all data).
- **All Environments**: Available but use with extreme caution in production

#### Run Migrations
```bash
rake db:migrate
```
- **Development/Test**: Runs all pending database migrations from `db/migrate/`
- **Production**: Only creates the `dataclips` table if it doesn't exist

#### Rollback Migration
```bash
rake db:rollback
```
Rolls back the last migration.

#### Seed Database
```bash
rake db:seed
```
- **Development/Test**: Runs the seed file (`db/seeds.rb`) to populate the database with sample data
- **Production**: Skipped (no seeding in production)

#### Setup Database
```bash
rake db:setup
```
Combines `db:create`, `db:migrate`, and `db:seed` in one command.
- **Development/Test**: Full setup with database creation and sample data
- **Production**: Respects production constraints (no creation, no seeding)

#### Setup Database for Production
```bash
rake db:setup_production
```
Production-specific setup task that:
- Assumes database already exists (connects via `DATABASE_URL`)
- Only creates the `dataclips` table if needed
- Skips all seeding
- Only runs when `RACK_ENV=production`

### Schema Management

#### Dump Schema
```bash
rake db:schema:dump
```
Exports the current database schema to `db/schema.rb`.

#### Load Schema
```bash
rake db:schema:load
```
Loads the schema from `db/schema.rb` (faster than running migrations).

#### Merge Migrations
```bash
rake db:schema:merge
```
Dumps the current schema and removes all migration files. Useful for cleaning up old migrations.

#### Rebuild Schema JSON
```bash
rake schema
```
Generates a JSON schema representation at `schema/schema.json`.

## Common Workflows

### First Time Setup - Development
```bash
# 1. Set up environment
cp env.example .env
# Edit .env with your database settings and set RACK_ENV=development

# 2. Setup database with sample data
rake db:setup
```

### First Time Setup - Production
```bash
# 1. Set environment variables (DATABASE_URL points to existing database)
export DATABASE_URL=postgres://user:pass@prod-host:5432/existing_db
export RACK_ENV=production

# 2. Setup only dataclips table (no database creation, no seeding)
rake db:setup_production
```

### Development Workflow
```bash
# After pulling new migrations
rake db:migrate

# Reset database with fresh data
rake db:drop db:setup

# Rollback a problematic migration
rake db:rollback
```

### Production Deployment
```bash
# Set production environment
export RACK_ENV=production

# Run dataclips setup only (safe for existing databases)
rake db:setup_production

# Or just run migrations (same effect in production)
rake db:migrate

# Generate schema documentation
rake schema
```

## Error Handling

All tasks include proper error handling and will exit with status code 1 on failure. Tasks that require a database connection will check for the `DATABASE_URL` environment variable and provide helpful error messages if it's missing.

## Environment Detection

The rake tasks automatically detect the current environment using the `RACK_ENV` environment variable:
- **Default**: `development` (if `RACK_ENV` is not set)
- **Development**: Full database management (create, migrate, seed)
- **Test**: Same as development (useful for testing)
- **Production**: Limited to dataclips table setup only

## Safety Features

### Production Safeguards
- **No Database Creation**: Production assumes database already exists
- **Limited Migrations**: Only dataclips-related migrations run
- **No Seeding**: Prevents accidental sample data insertion
- **Explicit Tasks**: `db:setup_production` makes production intent clear

### Development Features  
- **Full Database Control**: Create, drop, migrate, seed operations
- **Sample Data**: Automatic seeding with realistic test data
- **Migration Testing**: Full migration suite for development

## Migration Files

Migrations should be placed in `db/migrate/` and follow the Sequel migration format:

```ruby
Sequel.migration do
  up do
    create_table :example do
      primary_key :id
      String :name, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  down do
    drop_table :example
  end
end
```
