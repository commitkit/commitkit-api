require 'rails_helper'

RSpec.describe "Sessions", type: :request do
  describe "GET /session/new" do
    it "returns success" do
      get new_session_path
      expect(response).to have_http_status(:success)
    end

    it "displays login form" do
      get new_session_path
      expect(response.body).to include("Sign in")
    end
  end

  describe "POST /session" do
    let!(:user) do
      User.create!(
        email_address: "test@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
    end

    context "with valid credentials" do
      let(:valid_params) do
        {
          email_address: "test@example.com",
          password: "password123"
        }
      end

      it "logs in the user" do
        post session_path, params: valid_params
        expect(response).to redirect_to(dashboard_path)
      end

      it "sets the session" do
        post session_path, params: valid_params
        follow_redirect!
        expect(response.body).to include("test@example.com")
      end
    end

    context "with invalid credentials" do
      it "does not log in with wrong password" do
        post session_path, params: {
          email_address: "test@example.com",
          password: "wrongpassword"
        }
        expect(response).to redirect_to(login_path)
      end

      it "does not log in with non-existent email" do
        post session_path, params: {
          email_address: "nonexistent@example.com",
          password: "password123"
        }
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "DELETE /session" do
    let!(:user) do
      User.create!(
        email_address: "test@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
    end

    context "when logged in" do
      before do
        post session_path, params: {
          email_address: "test@example.com",
          password: "password123"
        }
      end

      it "logs out the user" do
        delete session_path
        expect(response).to redirect_to(login_path)
      end

      it "clears the session" do
        delete session_path
        follow_redirect!
        # After logout, trying to access dashboard should redirect to login
        get dashboard_path
        expect(response).to redirect_to(login_path)
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        delete session_path
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
