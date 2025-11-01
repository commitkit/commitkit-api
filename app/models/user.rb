class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :commits, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true

  # Generate API token before creating user
  before_create :generate_api_token

  def regenerate_api_token!
    update!(api_token: generate_token)
  end

  private

  def generate_api_token
    self.api_token = generate_token
  end

  def generate_token
    SecureRandom.urlsafe_base64(32)
  end
end
