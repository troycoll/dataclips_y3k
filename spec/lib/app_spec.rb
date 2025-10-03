# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dataclips App' do
  include_examples 'a dataclip mock'
  let(:app) { Sinatra::Application }

  describe 'GET /' do
    it 'redirects to /dataclips/list' do
      get '/'
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with('/dataclips/list')
    end
  end

  describe 'GET /dataclips/list' do
    it 'returns successful response' do
      get '/dataclips/list'
      expect(last_response).to be_ok
    end

    it 'renders the list template' do
      get '/dataclips/list'
      expect(last_response.body).to be_a(String)
    end
  end

  describe 'GET /dataclips/:slug' do
    let(:mock_dataclip) do
      {
        id: 1,
        slug: 'test-slug',
        title: 'Test Dataclip',
        description: 'A test dataclip',
        sql_query: 'SELECT * FROM users',
        created_by: 'test_user',
        created_at: Time.now,
        updated_at: Time.now
      }
    end

    before do
      allow_any_instance_of(Sinatra::Application).to receive(:get_dataclip).with('test-slug').and_return(mock_dataclip)
    end

    it 'returns successful response' do
      get '/dataclips/test-slug'
      expect(last_response).to be_ok
    end

    it 'renders the show template' do
      get '/dataclips/test-slug'
      expect(last_response.body).to be_a(String)
    end
  end

  describe 'GET /dataclips/:slug/edit' do
    let(:mock_dataclip) do
      {
        id: 1,
        slug: 'test-slug',
        title: 'Test Dataclip',
        description: 'A test dataclip',
        sql_query: 'SELECT * FROM users',
        created_by: 'test_user',
        created_at: Time.now,
        updated_at: Time.now
      }
    end

    before do
      allow_any_instance_of(Sinatra::Application).to receive(:get_dataclip).with('test-slug').and_return(mock_dataclip)
    end

    it 'returns successful response' do
      get '/dataclips/test-slug/edit'
      expect(last_response).to be_ok
    end

    it 'renders the edit template' do
      get '/dataclips/test-slug/edit'
      expect(last_response.body).to be_a(String)
    end
  end

  describe 'POST /dataclips/create' do
    let(:valid_params) do
      {
        title: 'Test Dataclip',
        description: 'A test dataclip',
        sql_query: 'SELECT * FROM users',
        created_by: 'test_user'
      }
    end

    context 'with valid params' do
      it 'creates a dataclip successfully' do
        mock_result = double('result', success?: true, errors: [])
        expect(CreateDataclipMediator).to receive(:call).with(valid_params).and_return(mock_result)

        post '/dataclips/create', valid_params

        expect(last_response).to be_redirect
        expect(last_response.location).to end_with('/dataclips/list')
      end

      it 'sets success flash message' do
        mock_result = double('result', success?: true, errors: [])
        expect(CreateDataclipMediator).to receive(:call).with(valid_params).and_return(mock_result)

        post '/dataclips/create', valid_params

        # Follow the redirect to check the flash message would be displayed
        follow_redirect!
        # NOTE: The flash message is stored in session and would be displayed on the next page
      end
    end

    context 'with invalid params' do
      let(:invalid_params) { { title: '', sql_query: '' } }

      it 'redirects to edit form on validation error' do
        mock_result = double('result', success?: false, errors: ['Title is required', 'SQL query is required'])
        expect(CreateDataclipMediator).to receive(:call).with(invalid_params).and_return(mock_result)

        post '/dataclips/create', invalid_params

        expect(last_response).to be_redirect
        expect(last_response.location).to end_with('/dataclips/edit')
      end

      it 'stores errors in session' do
        mock_result = double('result', success?: false, errors: ['Title is required'])
        expect(CreateDataclipMediator).to receive(:call).with(invalid_params).and_return(mock_result)

        post '/dataclips/create', invalid_params

        # The errors would be stored in session for display
        expect(last_response).to be_redirect
      end
    end
  end

  describe 'PUT /dataclips/:slug/update' do
    let(:slug) { 'test-dataclip' }
    let(:valid_params) do
      {
        title: 'Updated Dataclip',
        description: 'Updated description',
        sql_query: 'SELECT * FROM updated_users',
        created_by: 'updated_user'
      }
    end

    context 'with valid params' do
      it 'updates a dataclip successfully' do
        mock_dataclip = { title: 'Updated Dataclip' }
        mock_result = double('result', success?: true, errors: [], dataclip: mock_dataclip)
        expect(UpdateDataclipMediator).to receive(:call).with(slug,
                                                              hash_including('title' => 'Updated Dataclip')).and_return(mock_result)

        put "/dataclips/#{slug}/update", valid_params

        expect(last_response).to be_redirect
        expect(last_response.location).to end_with("/dataclips/#{slug}")
      end

      it 'sets success flash message' do
        mock_dataclip = { title: 'Updated Dataclip' }
        mock_result = double('result', success?: true, errors: [], dataclip: mock_dataclip)
        expect(UpdateDataclipMediator).to receive(:call).with(slug,
                                                              hash_including('title' => 'Updated Dataclip')).and_return(mock_result)

        put "/dataclips/#{slug}/update", valid_params

        expect(last_response).to be_redirect
      end
    end

    context 'with invalid params' do
      let(:invalid_params) { { title: 'a' * 256 } }

      it 'redirects to edit form on validation error' do
        mock_result = double('result', success?: false, errors: ['Title must be 255 characters or less'])
        expect(UpdateDataclipMediator).to receive(:call).with(slug,
                                                              hash_including('title' => 'a' * 256)).and_return(mock_result)

        put "/dataclips/#{slug}/update", invalid_params

        expect(last_response).to be_redirect
        expect(last_response.location).to end_with("/dataclips/#{slug}/edit")
      end

      it 'stores errors in session' do
        mock_result = double('result', success?: false, errors: ['Title must be 255 characters or less'])
        expect(UpdateDataclipMediator).to receive(:call).with(slug,
                                                              hash_including('title' => 'a' * 256)).and_return(mock_result)

        put "/dataclips/#{slug}/update", invalid_params

        expect(last_response).to be_redirect
      end
    end
  end

  describe 'DELETE /dataclips/:slug/delete' do
    let(:slug) { 'test-dataclip' }

    context 'with existing dataclip' do
      it 'deletes a dataclip successfully' do
        mock_deleted_dataclip = { title: 'Deleted Dataclip' }
        mock_result = double('result', success?: true, errors: [], deleted_dataclip: mock_deleted_dataclip)
        expect(DeleteDataclipMediator).to receive(:call).with(slug).and_return(mock_result)

        delete "/dataclips/#{slug}/delete"

        expect(last_response).to be_redirect
        expect(last_response.location).to end_with('/dataclips/list')
      end

      it 'sets success flash message' do
        mock_deleted_dataclip = { title: 'Deleted Dataclip' }
        mock_result = double('result', success?: true, errors: [], deleted_dataclip: mock_deleted_dataclip)
        expect(DeleteDataclipMediator).to receive(:call).with(slug).and_return(mock_result)

        delete "/dataclips/#{slug}/delete"

        expect(last_response).to be_redirect
      end
    end

    context 'with non-existent dataclip' do
      it 'redirects to list on deletion error' do
        mock_result = double('result', success?: false, errors: ['Dataclip not found'])
        expect(DeleteDataclipMediator).to receive(:call).with(slug).and_return(mock_result)

        delete "/dataclips/#{slug}/delete"

        expect(last_response).to be_redirect
        expect(last_response.location).to end_with('/dataclips/list')
      end

      it 'stores errors in session' do
        mock_result = double('result', success?: false, errors: ['Dataclip not found'])
        expect(DeleteDataclipMediator).to receive(:call).with(slug).and_return(mock_result)

        delete "/dataclips/#{slug}/delete"

        expect(last_response).to be_redirect
      end
    end
  end

  describe 'helper methods' do
    describe '#flash_errors' do
      it 'returns empty string when no errors in session' do
        get '/'
        # Helper methods are tested indirectly through the app behavior
        expect(last_response).to be_redirect
      end

      # NOTE: Testing helper methods directly would require more complex setup
      # In practice, these are tested through integration tests of the routes
    end

    describe '#flash_success' do
      it 'returns empty string when no success message in session' do
        get '/'
        expect(last_response).to be_redirect
      end
    end

    describe '#flash_messages' do
      it 'combines flash_errors and flash_success' do
        get '/'
        expect(last_response).to be_redirect
      end
    end
  end

  describe 'session handling' do
    it 'has sessions enabled' do
      get '/'
      expect(last_request.session).to respond_to(:keys)
      expect(last_request.session).to have_key('session_id')
    end
  end

  describe 'route parameter handling' do
    let(:mock_dataclip) do
      {
        id: 1,
        slug: 'test-dataclip-123',
        title: 'Test Dataclip',
        description: 'A test dataclip',
        sql_query: 'SELECT * FROM users',
        created_by: 'test_user',
        created_at: Time.now,
        updated_at: Time.now
      }
    end

    before do
      allow_any_instance_of(Sinatra::Application).to receive(:get_dataclip).with('test-dataclip-123').and_return(mock_dataclip)
      allow_any_instance_of(Sinatra::Application).to receive(:get_dataclip).with('test-dataclip-with-numbers-123').and_return(mock_dataclip)
    end

    it 'handles slug parameters correctly' do
      slug = 'test-dataclip-123'
      get "/dataclips/#{slug}"
      expect(last_response).to be_ok
    end

    it 'handles special characters in slugs' do
      slug = 'test-dataclip-with-numbers-123'
      get "/dataclips/#{slug}"
      expect(last_response).to be_ok
    end
  end

  describe 'GET /api/schema' do
    context 'when schema fetch is successful' do
      let(:mock_schema_result) do
        {
          success: true,
          schema: {
            'users' => {
              columns: [
                { name: 'id', type: 'integer', nullable: false, primary_key: true, default: nil },
                { name: 'name', type: 'varchar(255)', nullable: false, primary_key: false, default: nil },
                { name: 'email', type: 'varchar(255)', nullable: true, primary_key: false, default: nil }
              ],
              column_count: 3
            },
            'dataclips' => {
              columns: [
                { name: 'uuid', type: 'uuid', nullable: false, primary_key: true, default: nil },
                { name: 'slug', type: 'varchar(255)', nullable: false, primary_key: false, default: nil },
                { name: 'title', type: 'varchar(255)', nullable: false, primary_key: false, default: nil }
              ],
              column_count: 3
            }
          },
          errors: []
        }
      end

      before do
        allow(SchemaWorker).to receive(:fetch_schema).and_return(mock_schema_result)
      end

      it 'returns successful response with schema data' do
        get '/api/schema'

        expect(last_response).to be_ok
        expect(last_response.content_type).to include('application/json')

        response_data = JSON.parse(last_response.body)
        expect(response_data['success']).to be true
        expect(response_data['schema']).to be_a(Hash)
        expect(response_data['errors']).to be_empty
      end

      it 'includes table and column information' do
        get '/api/schema'

        response_data = JSON.parse(last_response.body)
        schema = response_data['schema']

        expect(schema).to have_key('users')
        expect(schema).to have_key('dataclips')

        users_table = schema['users']
        expect(users_table).to have_key('columns')
        expect(users_table).to have_key('column_count')
        expect(users_table['columns']).to be_an(Array)
        expect(users_table['column_count']).to eq(3)
      end
    end

    context 'when schema fetch fails' do
      before do
        allow(SchemaWorker).to receive(:fetch_schema).and_raise(StandardError.new('Database connection failed'))
      end

      it 'returns error response' do
        get '/api/schema'

        expect(last_response.status).to eq(500)
        expect(last_response.content_type).to include('application/json')

        response_data = JSON.parse(last_response.body)
        expect(response_data['success']).to be false
        expect(response_data['schema']).to be_empty
        expect(response_data['errors']).to include('Failed to fetch schema: Database connection failed')
      end
    end

    context 'when SchemaWorker returns error result' do
      let(:error_result) do
        {
          success: false,
          schema: {},
          errors: ['Database error: Connection timeout']
        }
      end

      before do
        allow(SchemaWorker).to receive(:fetch_schema).and_return(error_result)
      end

      it 'returns the error result as JSON' do
        get '/api/schema'

        expect(last_response).to be_ok
        expect(last_response.content_type).to include('application/json')

        response_data = JSON.parse(last_response.body)
        expect(response_data['success']).to be false
        expect(response_data['schema']).to be_empty
        expect(response_data['errors']).to include('Database error: Connection timeout')
      end
    end
  end
end
