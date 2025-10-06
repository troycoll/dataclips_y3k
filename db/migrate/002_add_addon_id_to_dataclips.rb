# frozen_string_literal: true

# Database migration: Add addon_id to dataclips table
# This allows associating a dataclip with a specific Heroku addon (database)
# Run with: bundle exec rake db:migrate

Sequel.migration do
  up do
    alter_table :dataclips do
      add_column :addon_id, String, null: true
      add_column :addon_name, String, null: true

      add_index :addon_id
    end
  end

  down do
    alter_table :dataclips do
      drop_index :addon_id
      drop_column :addon_id
      drop_column :addon_name
    end
  end
end
