class Repository < ApplicationRecord
  belongs_to :user
  has_many :commits, dependent: :destroy

  validates :url, presence: true, uniqueness: { scope: :user_id }
end
