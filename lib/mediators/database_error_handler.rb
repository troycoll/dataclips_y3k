# frozen_string_literal: true

# Shared module for consistent database error handling across mediators
module DatabaseErrorHandler
  private

  def handle_database_operation
    yield
  rescue Sequel::DatabaseError => e
    add_error("Database error: #{e.message}")
  rescue StandardError => e
    add_error("Unexpected error: #{e.message}")
  end
end
