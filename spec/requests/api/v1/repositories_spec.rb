require 'rails_helper'

RSpec.describe "Api::V1::Repositories", type: :request do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123", password_confirmation: "password123") }
  let(:api_token) { user.api_token }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "DELETE /api/v1/repositories/:id" do
    let!(:repo_a) { create(:repository, user: user, url: "https://github.com/user/repo-a") }
    let!(:repo_b) { create(:repository, user: user, url: "https://github.com/user/repo-b") }

    context "with valid authentication" do
      before do
        # Commits for repo A
        create(:commit, user: user, repository: repo_a, commit_hash: "abc123", message: "First commit")
        create(:commit, user: user, repository: repo_a, commit_hash: "def456", message: "Second commit")
        create(:commit, user: user, repository: repo_a, commit_hash: "ghi789", message: "Third commit")

        # Commits for repo B (should not be deleted)
        create(:commit, user: user, repository: repo_b, commit_hash: "jkl012", message: "Fourth commit")
      end

      it "deletes the repository and all its commits" do
        expect {
          delete "/api/v1/repositories/#{repo_a.id}", headers: headers
        }.to change { user.repositories.count }.by(-1)
         .and change { user.commits.count }.from(4).to(1)

        expect(response).to have_http_status(:ok)
        expect(json_response['message']).to eq('Repository and all associated commits deleted successfully')
      end

      it "does not delete commits from other repositories" do
        delete "/api/v1/repositories/#{repo_a.id}", headers: headers

        remaining_commit = user.commits.find_by(commit_hash: "jkl012")
        expect(remaining_commit).to be_present
        expect(remaining_commit.repository).to eq(repo_b)
      end

      it "does not allow deleting other users' repositories" do
        other_user = create(:user, email_address: "other@example.com")
        other_repo = create(:repository, user: other_user, url: "https://github.com/other/repo")
        create(:commit, user: other_user, repository: other_repo, commit_hash: "xyz789")

        delete "/api/v1/repositories/#{other_repo.id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(other_repo.reload).to be_present
      end

      it "returns not found for non-existent repository" do
        delete "/api/v1/repositories/99999", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with invalid authentication" do
      it "returns unauthorized" do
        delete "/api/v1/repositories/#{repo_a.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
