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

      it "displays link to settings" do
        get dashboard_path
        expect(response.body).to include("Settings")
        expect(response.body).to include(settings_path)
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

      it "filters commits by repository when repository_id parameter is provided" do
        repo1 = create(:repository, user: user, url: "https://github.com/user/repo1.git", name: "repo1")
        repo2 = create(:repository, user: user, url: "https://github.com/user/repo2.git", name: "repo2")

        commit1 = user.commits.create!(repository: repo1, commit_hash: "abc123", message: "Commit in repo1", summary: "Summary 1")
        commit2 = user.commits.create!(repository: repo2, commit_hash: "def456", message: "Commit in repo2", summary: "Summary 2")
        commit3 = user.commits.create!(repository: repo1, commit_hash: "ghi789", message: "Another commit in repo1", summary: "Summary 3")

        get dashboard_path, params: { repository_id: repo1.id }

        expect(response.body).to include("Commit in repo1")
        expect(response.body).to include("Another commit in repo1")
        expect(response.body).not_to include("Commit in repo2")
      end

      it "shows all repositories in filter dropdown" do
        repo1 = create(:repository, user: user, url: "https://github.com/user/repo1.git", name: "repo1")
        repo2 = create(:repository, user: user, url: "https://github.com/user/repo2.git", name: "repo2")

        get dashboard_path

        expect(response.body).to include("repo1")
        expect(response.body).to include("repo2")
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
