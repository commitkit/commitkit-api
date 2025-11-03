require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_many(:sessions).dependent(:destroy) }
    it { should have_many(:commits).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:email_address) }

    it 'validates uniqueness of email_address' do
      create(:user, email_address: 'test@example.com')
      duplicate_user = build(:user, email_address: 'test@example.com')

      expect(duplicate_user).not_to be_valid
      expect(duplicate_user.errors[:email_address]).to include('has already been taken')
    end

    it 'validates email_address case-insensitively' do
      create(:user, email_address: 'test@example.com')
      duplicate_user = build(:user, email_address: 'TEST@EXAMPLE.COM')

      expect(duplicate_user).not_to be_valid
    end
  end

  describe 'email normalization' do
    it 'normalizes email to lowercase' do
      user = create(:user, email_address: 'TEST@EXAMPLE.COM')
      expect(user.email_address).to eq('test@example.com')
    end

    it 'strips whitespace from email' do
      user = create(:user, email_address: '  test@example.com  ')
      expect(user.email_address).to eq('test@example.com')
    end
  end

  describe 'api_token generation' do
    it 'generates api_token before creation' do
      user = build(:user)
      expect(user.api_token).to be_nil

      user.save!
      expect(user.api_token).to be_present
      expect(user.api_token.length).to be > 20
    end

    it 'generates unique api_token for each user' do
      user1 = create(:user)
      user2 = create(:user)

      expect(user1.api_token).not_to eq(user2.api_token)
    end
  end

  describe '#regenerate_api_token!' do
    it 'generates a new api_token' do
      user = create(:user)
      old_token = user.api_token

      user.regenerate_api_token!

      expect(user.api_token).not_to eq(old_token)
      expect(user.api_token).to be_present
    end

    it 'persists the new token to the database' do
      user = create(:user)
      user.regenerate_api_token!

      expect(user.reload.api_token).to eq(user.api_token)
    end
  end

  describe 'password' do
    it 'requires password on creation' do
      user = build(:user, password: nil, password_confirmation: nil)
      expect(user).not_to be_valid
    end

    it 'authenticates with correct password' do
      user = create(:user, password: 'password123', password_confirmation: 'password123')
      expect(user.authenticate('password123')).to eq(user)
    end

    it 'does not authenticate with incorrect password' do
      user = create(:user, password: 'password123', password_confirmation: 'password123')
      expect(user.authenticate('wrong')).to be false
    end
  end

  describe 'dependent destroy' do
    it 'destroys associated commits when user is destroyed' do
      user = create(:user)
      commit = create(:commit, user: user)

      expect { user.destroy }.to change(Commit, :count).by(-1)
    end

    it 'destroys associated sessions when user is destroyed' do
      user = create(:user)
      session = user.sessions.create!(user_agent: 'Test', ip_address: '127.0.0.1')

      expect { user.destroy }.to change(Session, :count).by(-1)
    end
  end
end
