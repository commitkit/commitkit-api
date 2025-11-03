require 'rails_helper'

RSpec.describe Commit, type: :model do
  let(:user) { create(:user) }

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    it { should validate_presence_of(:commit_hash) }
    it { should validate_presence_of(:message) }

    it 'validates uniqueness of commit_hash' do
      create(:commit, commit_hash: 'abc123', user: user)
      duplicate_commit = build(:commit, commit_hash: 'abc123', user: user)

      expect(duplicate_commit).not_to be_valid
      expect(duplicate_commit.errors[:commit_hash]).to include('has already been taken')
    end
  end

  describe 'attributes' do
    it 'belongs to a repository' do
      repository = create(:repository, user: user, url: 'https://github.com/user/repo')
      commit = user.commits.create!(
        commit_hash: 'abc123',
        message: 'Test commit',
        summary: 'Test summary',
        repository: repository
      )

      expect(commit.repository).to eq(repository)
      expect(commit.repository.url).to eq('https://github.com/user/repo')
    end

    it 'requires a repository' do
      commit = user.commits.build(
        commit_hash: 'abc123',
        message: 'Test commit',
        summary: 'Test summary'
      )

      expect(commit).not_to be_valid
      expect(commit.errors[:repository]).to be_present
    end
  end
end
