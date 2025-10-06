# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/clients/heroku'

RSpec.describe HerokuClient do
  let(:api_token) { 'test-api-token-12345' }
  let(:app_name) { 'test-app' }
  let(:mock_platform_api) { instance_double(PlatformAPI::Client) }
  let(:mock_addon_client) { double('addon_client') }
  let(:mock_config_var_client) { double('config_var_client') }
  let(:mock_account_client) { double('account_client') }

  before do
    # Set environment variable for tests
    ENV['HEROKU_API_TOKEN'] = api_token

    # Mock PlatformAPI connection
    allow(PlatformAPI).to receive(:connect_oauth).with(api_token).and_return(mock_platform_api)
    allow(mock_platform_api).to receive(:addon).and_return(mock_addon_client)
    allow(mock_platform_api).to receive(:config_var).and_return(mock_config_var_client)
    allow(mock_platform_api).to receive(:account).and_return(mock_account_client)
  end

  after do
    ENV.delete('HEROKU_API_TOKEN')
  end

  describe '#initialize' do
    context 'when API token is provided' do
      it 'initializes with the provided token' do
        allow(PlatformAPI).to receive(:connect_oauth).with('custom-token').and_return(mock_platform_api)
        described_class.new(api_token: 'custom-token')
        expect(PlatformAPI).to have_received(:connect_oauth).with('custom-token')
      end
    end

    context 'when API token is from environment' do
      it 'initializes with ENV token' do
        described_class.new
        expect(PlatformAPI).to have_received(:connect_oauth).with(api_token)
      end
    end

    context 'when API token is missing' do
      before do
        ENV.delete('HEROKU_API_TOKEN')
      end

      it 'raises ConfigurationError' do
        expect { described_class.new }.to raise_error(
          HerokuClient::ConfigurationError,
          'HEROKU_API_TOKEN environment variable is required'
        )
      end
    end

    context 'when API token is empty string' do
      before do
        ENV['HEROKU_API_TOKEN'] = ''
      end

      it 'raises ConfigurationError' do
        expect { described_class.new }.to raise_error(
          HerokuClient::ConfigurationError,
          'HEROKU_API_TOKEN environment variable is required'
        )
      end
    end
  end

  describe '#fetch_addons' do
    let(:client) { described_class.new }
    let(:addons_response) do
      [
        {
          'id' => '12345678-1234-1234-1234-123456789abc',
          'name' => 'postgresql-vertical-12345',
          'addon_service' => { 'name' => 'heroku-postgresql' },
          'plan' => { 'name' => 'heroku-postgresql:standard-0' },
          'created_at' => '2024-01-01T00:00:00Z',
          'updated_at' => '2024-01-01T00:00:00Z'
        },
        {
          'id' => '87654321-4321-4321-4321-cba987654321',
          'name' => 'redis-cylindrical-54321',
          'addon_service' => { 'name' => 'heroku-redis' },
          'plan' => { 'name' => 'heroku-redis:premium-0' },
          'created_at' => '2024-01-02T00:00:00Z',
          'updated_at' => '2024-01-02T00:00:00Z'
        }
      ]
    end

    context 'when request is successful' do
      before do
        allow(mock_addon_client).to receive(:list).with(app_name).and_return(addons_response)
      end

      it 'returns array of addons' do
        result = client.fetch_addons(app_name)
        expect(result).to eq(addons_response)
        expect(result.length).to eq(2)
      end

      it 'calls the platform API addon list method' do
        client.fetch_addons(app_name)
        expect(mock_addon_client).to have_received(:list).with(app_name)
      end
    end

    context 'when app is not found' do
      before do
        allow(mock_addon_client).to receive(:list).with(app_name).and_raise(
          Excon::Error::NotFound.new('Not Found')
        )
      end

      it 'raises HerokuAPIError with app not found message' do
        expect { client.fetch_addons(app_name) }.to raise_error(
          HerokuClient::HerokuAPIError,
          /App 'test-app' not found/
        )
      end
    end

    context 'when API request fails' do
      before do
        allow(mock_addon_client).to receive(:list).with(app_name).and_raise(
          Excon::Error::BadRequest.new('Bad Request')
        )
      end

      it 'raises HerokuAPIError' do
        expect { client.fetch_addons(app_name) }.to raise_error(
          HerokuClient::HerokuAPIError,
          /Failed to fetch addons for app/
        )
      end
    end

    context 'when app_name is nil' do
      it 'raises ArgumentError' do
        expect { client.fetch_addons(nil) }.to raise_error(
          ArgumentError,
          'app_name cannot be nil or empty'
        )
      end
    end

    context 'when app_name is empty string' do
      it 'raises ArgumentError' do
        expect { client.fetch_addons('') }.to raise_error(
          ArgumentError,
          'app_name cannot be nil or empty'
        )
      end
    end

    context 'when app_name is whitespace' do
      it 'raises ArgumentError' do
        expect { client.fetch_addons('   ') }.to raise_error(
          ArgumentError,
          'app_name cannot be nil or empty'
        )
      end
    end
  end

  describe '#fetch_addon' do
    let(:client) { described_class.new }
    let(:addon_id) { '12345678-1234-1234-1234-123456789abc' }
    let(:addon_response) do
      {
        'id' => addon_id,
        'name' => 'postgresql-vertical-12345',
        'addon_service' => { 'name' => 'heroku-postgresql' },
        'plan' => { 'name' => 'heroku-postgresql:standard-0' },
        'created_at' => '2024-01-01T00:00:00Z',
        'updated_at' => '2024-01-01T00:00:00Z'
      }
    end

    context 'when request is successful' do
      before do
        allow(mock_addon_client).to receive(:info).with(app_name, addon_id).and_return(addon_response)
      end

      it 'returns addon details' do
        result = client.fetch_addon(app_name, addon_id)
        expect(result).to eq(addon_response)
      end

      it 'calls the platform API addon info method' do
        client.fetch_addon(app_name, addon_id)
        expect(mock_addon_client).to have_received(:info).with(app_name, addon_id)
      end
    end

    context 'when addon is not found' do
      before do
        allow(mock_addon_client).to receive(:info).with(app_name, addon_id).and_raise(
          Excon::Error::NotFound.new('Not Found')
        )
      end

      it 'raises HerokuAPIError with addon not found message' do
        expect { client.fetch_addon(app_name, addon_id) }.to raise_error(
          HerokuClient::HerokuAPIError,
          /Addon '#{addon_id}' not found for app/
        )
      end
    end

    context 'when addon_id is nil' do
      it 'raises ArgumentError' do
        expect { client.fetch_addon(app_name, nil) }.to raise_error(
          ArgumentError,
          'addon identifier cannot be nil or empty'
        )
      end
    end
  end

  describe '#fetch_postgres_addons' do
    let(:client) { described_class.new }
    let(:addons_response) do
      [
        {
          'id' => '12345678-1234-1234-1234-123456789abc',
          'name' => 'postgresql-vertical-12345',
          'addon_service' => { 'name' => 'heroku-postgresql' },
          'plan' => { 'name' => 'heroku-postgresql:standard-0' }
        },
        {
          'id' => '87654321-4321-4321-4321-cba987654321',
          'name' => 'redis-cylindrical-54321',
          'addon_service' => { 'name' => 'heroku-redis' },
          'plan' => { 'name' => 'heroku-redis:premium-0' }
        },
        {
          'id' => 'abcdef12-3456-7890-abcd-ef1234567890',
          'name' => 'postgresql-round-99999',
          'addon_service' => { 'name' => 'heroku-postgresql' },
          'plan' => { 'name' => 'heroku-postgresql:hobby-dev' }
        }
      ]
    end

    before do
      allow(mock_addon_client).to receive(:list).with(app_name).and_return(addons_response)
    end

    it 'returns only PostgreSQL addons' do
      result = client.fetch_postgres_addons(app_name)
      expect(result.length).to eq(2)
      expect(result.map { |a| a['id'] }).to contain_exactly(
        '12345678-1234-1234-1234-123456789abc',
        'abcdef12-3456-7890-abcd-ef1234567890'
      )
    end

    it 'filters out non-PostgreSQL addons' do
      result = client.fetch_postgres_addons(app_name)
      redis_addon = result.find { |a| a['addon_service']['name'] == 'heroku-redis' }
      expect(redis_addon).to be_nil
    end
  end

  describe '#postgres_addon?' do
    let(:client) { described_class.new }

    context 'when addon is PostgreSQL' do
      let(:postgres_addon) do
        { 'addon_service' => { 'name' => 'heroku-postgresql' } }
      end

      it 'returns true' do
        expect(client.postgres_addon?(postgres_addon)).to be true
      end
    end

    context 'when addon service name contains postgres in different case' do
      let(:postgres_addon) do
        { 'addon_service' => { 'name' => 'HEROKU-POSTGRESQL' } }
      end

      it 'returns true' do
        expect(client.postgres_addon?(postgres_addon)).to be true
      end
    end

    context 'when addon is not PostgreSQL' do
      let(:redis_addon) do
        { 'addon_service' => { 'name' => 'heroku-redis' } }
      end

      it 'returns false' do
        expect(client.postgres_addon?(redis_addon)).to be false
      end
    end

    context 'when addon_service is missing' do
      let(:invalid_addon) { {} }

      it 'returns false' do
        expect(client.postgres_addon?(invalid_addon)).to be false
      end
    end

    context 'when addon_service name is nil' do
      let(:invalid_addon) do
        { 'addon_service' => { 'name' => nil } }
      end

      it 'returns false' do
        expect(client.postgres_addon?(invalid_addon)).to be false
      end
    end
  end

  describe '#fetch_addon_config' do
    let(:client) { described_class.new }
    let(:addon_id) { '12345678-1234-1234-1234-123456789abc' }
    let(:addon_name) { 'postgresql-vertical-12345' }
    let(:addon_response) do
      {
        'id' => addon_id,
        'name' => addon_name,
        'addon_service' => { 'name' => 'heroku-postgresql' }
      }
    end
    let(:config_vars) do
      {
        'DATABASE_URL' => 'postgres://user:pass@host:5432/db',
        'POSTGRESQL_VERTICAL_12345_URL' => 'postgres://user:pass@host:5432/db',
        'REDIS_URL' => 'redis://localhost:6379',
        'SOME_OTHER_VAR' => 'value'
      }
    end

    before do
      allow(mock_addon_client).to receive(:info).with(app_name, addon_id).and_return(addon_response)
      allow(mock_config_var_client).to receive(:info_for_app).with(app_name).and_return(config_vars)
    end

    it 'returns config vars related to the addon' do
      result = client.fetch_addon_config(app_name, addon_id)
      expect(result).to have_key('POSTGRESQL_VERTICAL_12345_URL')
      expect(result).not_to have_key('REDIS_URL')
      expect(result).not_to have_key('SOME_OTHER_VAR')
    end

    it 'calls the platform API methods' do
      client.fetch_addon_config(app_name, addon_id)
      expect(mock_addon_client).to have_received(:info).with(app_name, addon_id)
      expect(mock_config_var_client).to have_received(:info_for_app).with(app_name)
    end
  end

  describe '#health_check' do
    let(:client) { described_class.new }
    let(:account_info) do
      {
        'id' => 'user-id',
        'email' => 'user@example.com'
      }
    end

    context 'when API is accessible' do
      before do
        allow(mock_account_client).to receive(:info).and_return(account_info)
      end

      it 'returns true' do
        expect(client.health_check).to be true
      end

      it 'calls account info endpoint' do
        client.health_check
        expect(mock_account_client).to have_received(:info)
      end
    end

    context 'when API is not accessible' do
      before do
        allow(mock_account_client).to receive(:info).and_raise(
          Excon::Error::Unauthorized.new('Unauthorized')
        )
      end

      it 'raises HerokuAPIError' do
        expect { client.health_check }.to raise_error(
          HerokuClient::HerokuAPIError,
          /Heroku API health check failed/
        )
      end
    end
  end

  describe '#account_info' do
    let(:client) { described_class.new }
    let(:account_response) do
      {
        'id' => 'user-id-12345',
        'email' => 'user@example.com',
        'name' => 'Test User'
      }
    end

    context 'when request is successful' do
      before do
        allow(mock_account_client).to receive(:info).and_return(account_response)
      end

      it 'returns account information' do
        result = client.account_info
        expect(result).to eq(account_response)
        expect(result['email']).to eq('user@example.com')
      end

      it 'calls the platform API account info method' do
        client.account_info
        expect(mock_account_client).to have_received(:info)
      end
    end

    context 'when API request fails' do
      before do
        allow(mock_account_client).to receive(:info).and_raise(
          Excon::Error::Unauthorized.new('Unauthorized')
        )
      end

      it 'raises HerokuAPIError' do
        expect { client.account_info }.to raise_error(
          HerokuClient::HerokuAPIError,
          /Failed to fetch account info/
        )
      end
    end
  end

  describe 'error handling' do
    let(:client) { described_class.new }

    context 'when an unexpected error occurs' do
      before do
        allow(mock_addon_client).to receive(:list).with(app_name).and_raise(
          StandardError.new('Unexpected error')
        )
      end

      it 'wraps the error in HerokuAPIError' do
        expect { client.fetch_addons(app_name) }.to raise_error(
          HerokuClient::HerokuAPIError,
          /Unexpected error fetching addons/
        )
      end
    end
  end
end
