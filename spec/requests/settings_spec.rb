require 'rails_helper'

RSpec.describe "Settings", type: :request do
  let(:user) { create(:user) }

  before do
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  describe "GET /settings" do
    it "displays settings page" do
      get settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Settings")
      expect(response.body).to include("API Token")
      expect(response.body).to include(user.api_token)
    end
  end
end
