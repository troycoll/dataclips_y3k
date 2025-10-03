# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/mediators/base_mediator'

RSpec.describe BaseMediator do
  let(:test_mediator_class) do
    Class.new(BaseMediator) do
      def call
        validate_presence(:name)
        validate_format(:email, /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i, 'Email format is invalid')
        self
      end
    end
  end

  describe '.call' do
    it 'creates an instance and calls #call' do
      mediator = test_mediator_class.call(name: 'Test')
      expect(mediator).to be_a(test_mediator_class)
    end
  end

  describe '#initialize' do
    it 'initializes with empty params by default' do
      mediator = described_class.new
      expect(mediator.send(:params)).to eq({})
    end

    it 'initializes with provided params' do
      params = { name: 'Test', email: 'test@example.com' }
      mediator = described_class.new(params)
      expect(mediator.send(:params)).to eq(params)
    end

    it 'initializes with empty errors array' do
      mediator = described_class.new
      expect(mediator.errors).to eq([])
    end
  end

  describe '#call' do
    it 'raises NotImplementedError when not overridden' do
      mediator = described_class.new
      expect { mediator.call }.to raise_error(NotImplementedError, 'Subclasses must implement #call')
    end
  end

  describe '#success?' do
    context 'when there are no errors' do
      it 'returns true' do
        mediator = test_mediator_class.new(name: 'Test', email: 'test@example.com')
        mediator.call
        expect(mediator.success?).to be true
      end
    end

    context 'when there are errors' do
      it 'returns false' do
        mediator = test_mediator_class.new(email: 'invalid-email')
        mediator.call
        expect(mediator.success?).to be false
      end
    end
  end

  describe '#errors' do
    it 'returns the errors array' do
      mediator = test_mediator_class.new
      mediator.call
      expect(mediator.errors).to be_an(Array)
    end
  end

  describe 'validation methods' do
    describe '#validate_presence' do
      context 'when field is present and not empty' do
        it 'does not add an error' do
          mediator = test_mediator_class.new(name: 'Test')
          mediator.call
          expect(mediator.errors).not_to include('name is required')
        end
      end

      context 'when field is missing' do
        it 'adds a default error message' do
          mediator = test_mediator_class.new
          mediator.call
          expect(mediator.errors).to include('name is required')
        end
      end

      context 'when field is empty string' do
        it 'adds a default error message' do
          mediator = test_mediator_class.new(name: '')
          mediator.call
          expect(mediator.errors).to include('name is required')
        end
      end

      context 'when field is whitespace only' do
        it 'adds a default error message' do
          mediator = test_mediator_class.new(name: '   ')
          mediator.call
          expect(mediator.errors).to include('name is required')
        end
      end

      context 'with custom error message' do
        let(:custom_mediator_class) do
          Class.new(BaseMediator) do
            def call
              validate_presence(:name, 'Name cannot be blank')
              self
            end
          end
        end

        it 'uses the custom error message' do
          mediator = custom_mediator_class.new
          mediator.call
          expect(mediator.errors).to include('Name cannot be blank')
        end
      end
    end

    describe '#validate_format' do
      context 'when field matches the pattern' do
        it 'does not add an error' do
          mediator = test_mediator_class.new(name: 'Test', email: 'test@example.com')
          mediator.call
          expect(mediator.errors).not_to include('Email format is invalid')
        end
      end

      context 'when field does not match the pattern' do
        it 'adds the specified error message' do
          mediator = test_mediator_class.new(name: 'Test', email: 'invalid-email')
          mediator.call
          expect(mediator.errors).to include('Email format is invalid')
        end
      end

      context 'when field is missing' do
        it 'adds the specified error message' do
          mediator = test_mediator_class.new(name: 'Test')
          mediator.call
          expect(mediator.errors).to include('Email format is invalid')
        end
      end

      context 'with default error message' do
        let(:format_mediator_class) do
          Class.new(BaseMediator) do
            def call
              validate_format(:code, /\A[A-Z]{3}\z/)
              self
            end
          end
        end

        it 'uses the default error message' do
          mediator = format_mediator_class.new(code: 'invalid')
          mediator.call
          expect(mediator.errors).to include('code format is invalid')
        end
      end
    end
  end

  describe 'utility methods' do
    describe '#slug_format?' do
      it 'returns true for valid slug format' do
        mediator = described_class.new
        expect(mediator.send(:slug_format?, 'valid-slug-123')).to be true
        expect(mediator.send(:slug_format?, 'simple')).to be true
        expect(mediator.send(:slug_format?, 'a1b2c3')).to be true
      end

      it 'returns false for invalid slug format' do
        mediator = described_class.new
        expect(mediator.send(:slug_format?, 'Invalid-Slug')).to be false
        expect(mediator.send(:slug_format?, 'slug_with_underscore')).to be false
        expect(mediator.send(:slug_format?, 'slug-')).to be false
        expect(mediator.send(:slug_format?, '-slug')).to be false
        expect(mediator.send(:slug_format?, 'slug--double')).to be false
      end
    end

    describe '#generate_slug' do
      it 'generates a 16-character alphanumeric string' do
        mediator = described_class.new
        slug = mediator.send(:generate_slug)
        expect(slug).to match(/\A[a-z0-9]{16}\z/)
      end

      it 'generates different slugs each time' do
        mediator = described_class.new
        slug1 = mediator.send(:generate_slug)
        slug2 = mediator.send(:generate_slug)
        expect(slug1).not_to eq(slug2)
      end
    end
  end
end
