require 'rails_helper'

RSpec.describe "Dashboard", type: :request do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123", password_confirmation: "password123") }

  describe "GET /dashboard" do
    context "when user is authenticated" do
      before do
        # Log in the user by posting to the session endpoint
        post session_path, params: {
          email_address: user.email_address,
          password: "password123"
        }
      end

      it "returns success" do
        get dashboard_path
        expect(response).to have_http_status(:success)
      end

      it "displays user email" do
        get dashboard_path
        expect(response.body).to include(user.email_address)
      end

      it "displays API token" do
        get dashboard_path
        expect(response.body).to include(user.api_token)
      end

      it "displays total commits count" do
        repo = create(:repository, user: user)
        user.commits.create!(repository: repo, commit_hash: "abc123", message: "Test commit", summary: "Test")
        user.commits.create!(repository: repo, commit_hash: "def456", message: "Another commit", summary: "Test 2")

        get dashboard_path
        expect(response.body).to include("2")
      end

      it "displays recent commits" do
        repo = create(:repository, user: user)
        commit = user.commits.create!(repository: repo, commit_hash: "abc123", message: "Test commit", summary: "Test summary")

        get dashboard_path
        expect(response.body).to include("Test commit")
        expect(response.body).to include("Test summary")
        expect(response.body).to include("abc123")
      end

      it "shows empty state when no commits" do
        get dashboard_path
        expect(response.body).to include("No commits yet")
      end
    end

    context "when user is not authenticated" do
      it "redirects to login" do
        get dashboard_path
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
