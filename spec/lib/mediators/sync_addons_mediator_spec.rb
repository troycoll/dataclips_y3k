# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/mediators/sync_addons_mediator'

RSpec.describe SyncAddonsMediator do
  let(:app_name) { 'test-app' }
  let(:heroku_client) { instance_double(HerokuClient) }

  before do
    # Clear the addons table before each test
    DB[:addons].delete
  end

  describe '.call' do
    context 'when HEROKU_APP_NAME is configured' do
      before do
        ENV['HEROKU_APP_NAME'] = app_name
        allow(HerokuClient).to receive(:new).and_return(heroku_client)
      end

      after do
        ENV.delete('HEROKU_APP_NAME')
      end

      context 'when Heroku API returns addons successfully' do
        let(:addons) do
          [
            {
              'id' => '12345678-1234-1234-1234-123456789abc',
              'name' => 'postgresql-vertical-12345',
              'addon_service' => { 'name' => 'heroku-postgresql' },
              'plan' => { 'name' => 'heroku-postgresql:standard-0' }
            },
            {
              'id' => '87654321-4321-4321-4321-cba987654321',
              'name' => 'redis-horizontal-98765',
              'addon_service' => { 'name' => 'heroku-redis' },
              'plan' => { 'name' => 'heroku-redis:premium-0' }
            }
          ]
        end

        before do
          allow(heroku_client).to receive(:fetch_addons).with(app_name).and_return(addons)
        end

        it 'syncs all addons to the database' do
          result = described_class.call

          expect(result.success?).to be true
          expect(result.synced_count).to eq(2)
          expect(result.skipped_count).to eq(0)
          expect(DB[:addons].count).to eq(2)
        end

        it 'stores addon UUID and name correctly' do
          described_class.call

          addon1 = DB[:addons].where(uuid: '12345678-1234-1234-1234-123456789abc').first
          expect(addon1[:name]).to eq('postgresql-vertical-12345')

          addon2 = DB[:addons].where(uuid: '87654321-4321-4321-4321-cba987654321').first
          expect(addon2[:name]).to eq('redis-horizontal-98765')
        end

        it 'sets created_at and updated_at timestamps' do
          described_class.call

          addon = DB[:addons].first
          expect(addon[:created_at]).to be_a(Time)
          expect(addon[:updated_at]).to be_a(Time)
        end

        context 'when addon already exists' do
          before do
            # Pre-insert an addon with old name
            DB[:addons].insert(
              uuid: '12345678-1234-1234-1234-123456789abc',
              name: 'old-name',
              created_at: Time.now - 86400,
              updated_at: Time.now - 86400
            )
          end

          it 'updates the existing addon' do
            described_class.call

            expect(DB[:addons].count).to eq(2)
            addon = DB[:addons].where(uuid: '12345678-1234-1234-1234-123456789abc').first
            expect(addon[:name]).to eq('postgresql-vertical-12345')
          end

          it 'updates the updated_at timestamp' do
            old_time = Time.now - 86400
            DB[:addons].where(uuid: '12345678-1234-1234-1234-123456789abc').update(updated_at: old_time)

            described_class.call

            addon = DB[:addons].where(uuid: '12345678-1234-1234-1234-123456789abc').first
            expect(addon[:updated_at]).to be > old_time
          end
        end
      end

      context 'when Heroku API returns empty array' do
        before do
          allow(heroku_client).to receive(:fetch_addons).with(app_name).and_return([])
        end

        it 'succeeds without syncing any addons' do
          result = described_class.call

          expect(result.success?).to be true
          expect(result.synced_count).to eq(0)
          expect(DB[:addons].count).to eq(0)
        end
      end

      context 'when Heroku API raises HerokuAPIError' do
        before do
          allow(heroku_client).to receive(:fetch_addons).and_raise(
            HerokuClient::HerokuAPIError, 'API request failed'
          )
        end

        it 'returns failure with error message' do
          result = described_class.call

          expect(result.success?).to be false
          expect(result.errors).to include('Failed to sync addons from Heroku: API request failed')
        end

        it 'does not modify the database' do
          described_class.call

          expect(DB[:addons].count).to eq(0)
        end
      end

      context 'when addon data is malformed' do
        let(:malformed_addons) do
          [
            {
              'id' => '12345678-1234-1234-1234-123456789abc',
              'name' => 'postgresql-vertical-12345'
            },
            {
              'id' => nil, # Missing ID
              'name' => 'bad-addon'
            },
            {
              'id' => '87654321-4321-4321-4321-cba987654321',
              'name' => nil # Missing name
            }
          ]
        end

        before do
          allow(heroku_client).to receive(:fetch_addons).with(app_name).and_return(malformed_addons)
        end

        it 'syncs valid addons and skips malformed ones' do
          result = described_class.call

          expect(result.success?).to be true
          expect(result.synced_count).to eq(1)
          expect(DB[:addons].count).to eq(1)
        end
      end
    end

    context 'when HEROKU_APP_NAME is not configured' do
      before do
        ENV.delete('HEROKU_APP_NAME')
      end

      it 'returns failure with configuration error' do
        result = described_class.call

        expect(result.success?).to be false
        expect(result.errors).to include(match(/HEROKU_APP_NAME environment variable is required/))
      end
    end

    context 'when HEROKU_API_TOKEN is not configured' do
      before do
        ENV['HEROKU_APP_NAME'] = app_name
        ENV.delete('HEROKU_API_TOKEN')
        allow(HerokuClient).to receive(:new).and_raise(
          HerokuClient::ConfigurationError, 'HEROKU_API_TOKEN environment variable is required'
        )
      end

      after do
        ENV.delete('HEROKU_APP_NAME')
      end

      it 'returns failure with configuration error' do
        result = described_class.call

        expect(result.success?).to be false
        expect(result.errors).to include(match(/Heroku API not configured/))
      end
    end

    context 'when app_name is provided as parameter' do
      let(:custom_app_name) { 'custom-app' }

      before do
        ENV.delete('HEROKU_APP_NAME')
        allow(HerokuClient).to receive(:new).and_return(heroku_client)
        allow(heroku_client).to receive(:fetch_addons).with(custom_app_name).and_return([])
      end

      it 'uses the provided app_name' do
        result = described_class.call(app_name: custom_app_name)

        expect(result.success?).to be true
        expect(heroku_client).to have_received(:fetch_addons).with(custom_app_name)
      end
    end
  end
end
