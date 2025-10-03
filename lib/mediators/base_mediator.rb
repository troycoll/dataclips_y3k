# frozen_string_literal: true

require_relative 'database_error_handler'

# Base mediator class for common functionality
class BaseMediator
  include DatabaseErrorHandler
  class << self
    def call(*args, **kwargs)
      new(*args, **kwargs).call
    end
  end

  def initialize(params = {})
    @params = params
    @errors = []
  end

  def call
    raise NotImplementedError, 'Subclasses must implement #call'
  end

  def success?
    @errors.empty?
  end

  attr_reader :errors

  private

  attr_reader :params

  def add_error(message)
    @errors << message
  end

  def validate_presence(field, message = nil)
    value = params[field]
    return if value && !value.to_s.strip.empty?

    add_error(message || "#{field} is required")
  end

  def validate_format(field, pattern, message = nil)
    value = params[field]
    return if value && value.match?(pattern)

    add_error(message || "#{field} format is invalid")
  end

  def slug_format?(value)
    value.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
  end

  def generate_slug
    # Generate a 16-character alphanumeric slug
    chars = ('a'..'z').to_a + ('0'..'9').to_a
    (0...16).map { chars.sample }.join
  end
end
