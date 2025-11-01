class Commit < ApplicationRecord
  belongs_to :user

  validates :commit_hash, presence: true, uniqueness: true
  validates :message, presence: true
end
