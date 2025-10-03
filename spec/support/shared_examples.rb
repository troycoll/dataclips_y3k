# frozen_string_literal: true

# Shared examples for common mediator patterns
RSpec.shared_examples 'a mediator with database error handling' do |mediator_class, _method_name, *args|
  let(:mock_table) { double('dataclips_table') }

  before do
    allow(DB).to receive(:[]).with(:dataclips).and_return(mock_table)
  end

  it 'handles Sequel::DatabaseError' do
    error = Sequel::DatabaseError.new('Database connection failed')
    setup_error_scenario(error)

    mediator = mediator_class.new(*args)
    mediator.call

    expect(mediator.success?).to be false
    expect(mediator.errors).to include('Database error: Database connection failed')
  end

  it 'handles StandardError' do
    error = StandardError.new('Unexpected error occurred')
    setup_error_scenario(error)

    mediator = mediator_class.new(*args)
    mediator.call

    expect(mediator.success?).to be false
    expect(mediator.errors).to include('Unexpected error: Unexpected error occurred')
  end
end

RSpec.shared_examples 'a mediator class method' do |mediator_class, *args|
  it 'creates an instance and calls #call' do
    # Mock the database operations to avoid actual database interaction
    allow(DB).to receive(:[]).with(:dataclips).and_return(double('table', where: double('where', first: nil), insert: 1, update: true, delete: true))
    
    result = mediator_class.call(*args)
    expect(result).to be_a(mediator_class)
  end
end

RSpec.shared_examples 'a successful mediator operation' do
  it 'returns self' do
    result = subject.call
    expect(result).to eq(subject)
  end

  it 'is successful' do
    subject.call
    expect(subject.success?).to be true
  end
end

RSpec.shared_examples 'a failed mediator operation' do |expected_errors|
  it 'returns self' do
    result = subject.call
    expect(result).to eq(subject)
  end

  it 'is not successful' do
    subject.call
    expect(subject.success?).to be false
  end

  it 'has expected errors' do
    subject.call
    expected_errors.each do |error|
      expect(subject.errors).to include(error)
    end
  end
end

RSpec.shared_examples 'a dataclip mock' do
  let(:mock_dataclip) do
    {
      id: 1,
      slug: 'test-dataclip-123',
      title: 'Test Dataclip',
      description: 'A test dataclip',
      sql_query: 'SELECT * FROM users',
      created_by: 'test_user',
      created_at: Time.now - 3600,
      updated_at: Time.now - 1800
    }
  end
end
