# frozen_string_literal: true

# Database migration: Create addons table
# This stores Heroku addons (databases) with their UUID and name
# Run with: bundle exec rake db:migrate

Sequel.migration do
  up do
    create_table :addons do
      primary_key :id
      column :uuid, :uuid, null: false, unique: true
      String :name, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :uuid, unique: true
      index :name
    end
  end

  down do
    drop_table :addons
  end
end
