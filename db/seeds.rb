# frozen_string_literal: true

# Database seeds file
# Run with: ruby db/seeds.rb

require_relative '../config/config'
require_relative '../lib/mediators/create_dataclip_mediator'

# Initialize the application configuration
Config.setup!

puts '🌱 Seeding database...'

# Sample dataclips for development
sample_dataclips = [
  {
    title: 'Total User Count',
    description: 'Get the total number of users in the system',
    sql_query: 'SELECT COUNT(*) as total_users FROM users;',
    created_by: 'admin'
  },
  {
    title: 'Recent User Signups',
    description: 'Users who signed up in the last 7 days',
    sql_query: 'SELECT id, email, created_at FROM users WHERE created_at >= NOW() - INTERVAL \'7 days\' ORDER BY created_at DESC;',
    created_by: 'admin'
  },
  {
    title: 'Monthly Revenue Report',
    description: 'Revenue breakdown by month for the current year',
    sql_query: 'SELECT DATE_TRUNC(\'month\', created_at) as month, SUM(amount) as revenue FROM orders WHERE created_at >= DATE_TRUNC(\'year\', NOW()) GROUP BY month ORDER BY month;',
    created_by: 'finance_team'
  }
]

# Clear existing sample data in development
if Config.development?
  puts '  - Clearing existing sample dataclips...'
  DB[:dataclips].where(created_by: %w[admin finance_team]).delete
end

# Insert sample dataclips
sample_dataclips.each do |dataclip|
  result = CreateDataclipMediator.call(dataclip)

  if result.success?
    puts "  ✓ Created dataclip: #{dataclip[:title]} (slug: #{result.dataclip})"
  else
    puts "  ❌ Failed to create dataclip: #{dataclip[:title]} - #{result.errors.join(', ')}"
  end
end

puts "✅ Database seeding completed! Created #{sample_dataclips.length} sample dataclips."
puts
puts 'Available dataclips:'
get_all_dataclips.each do |dataclip|
  puts "  - #{dataclip[:slug]}: #{dataclip[:title]}"
end
