class Commit < ApplicationRecord
  belongs_to :user
  belongs_to :repository

  validates :commit_hash, presence: true, uniqueness: true
  validates :message, presence: true
end
