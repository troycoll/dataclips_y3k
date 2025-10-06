# frozen_string_literal: true

# Puma web server configuration
# See: https://puma.io/puma/file.CONFIGURATION.html

# Set the environment in which the rack's app will run
environment ENV.fetch('RACK_ENV', 'development')

# Number of worker processes for cluster mode
# Heroku recommends WEB_CONCURRENCY based on dyno size
workers ENV.fetch('WEB_CONCURRENCY', 2).to_i

# Daemonize the server into the background
# daemonize

# Store the pid of the server in the file at "path"
# pidfile 'tmp/pids/puma.pid'

# Use "path" as the file to store the server info state
# state_path 'tmp/pids/puma.state'

# Redirect STDOUT and STDERR to files
# stdout_redirect 'log/puma.stdout.log', 'log/puma.stderr.log', true

# Configure "min" to be the minimum number of threads to use to answer
# requests and "max" the maximum
threads_count = ENV.fetch('PUMA_THREADS', 5).to_i
threads threads_count, threads_count

# Bind the server to "url"
port ENV.fetch('PORT', 4567)
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 4567)}"

# Instead of "bind 'tcp://0.0.0.0:9292'" you
# can also use "port 9292"

# Code to run before doing a restart
# on_restart do
#   puts 'On restart...'
# end

# Code to run before forking workers
before_fork do
  # Close database connections before forking
  # This prevents connection sharing between parent and child processes
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base)
end

# Code to run when a worker boots to setup the process before booting
# the app
on_worker_boot do
  # Reconnect to database after forking
  # Each worker needs its own connection pool
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
end
