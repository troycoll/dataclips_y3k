# frozen_string_literal: true

# Database migration: Create dataclips table
# Run with: sequel -m db/migrate postgres://user:pass@host/db

Sequel.migration do
  up do
    create_table :dataclips do
      primary_key :uuid, :uuid, default: Sequel.function(:uuid_generate_v4)
      String :slug, null: false
      String :title, null: false
      Text :description
      Text :sql_query, null: false
      String :created_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug
      index :created_by
    end
  end

  down do
    drop_table :dataclips
  end
end
