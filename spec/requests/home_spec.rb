require 'rails_helper'

RSpec.describe "Home", type: :request do
  describe "GET /" do
    context "when not logged in" do
      it "returns success" do
        get root_path
        expect(response).to have_http_status(:success)
      end

      it "displays landing page content" do
        get root_path
        expect(response.body).to include("Track Your Git Commits")
        expect(response.body).to include("Build Better")
      end

      it "shows sign up and sign in buttons" do
        get root_path
        expect(response.body).to include("Get Started Free")
        expect(response.body).to include("Sign In")
      end
    end

    context "when logged in" do
      let!(:user) do
        User.create!(
          email_address: "test@example.com",
          password: "password123",
          password_confirmation: "password123"
        )
      end

      before do
        post session_path, params: {
          email_address: "test@example.com",
          password: "password123"
        }
      end

      it "redirects to dashboard" do
        get root_path
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end
end
