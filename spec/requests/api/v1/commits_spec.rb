require 'rails_helper'

RSpec.describe "Api::V1::Commits", type: :request do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123", password_confirmation: "password123") }
  let(:api_token) { user.api_token }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "POST /api/v1/commits" do
    context "with valid authentication" do
      let(:valid_params) do
        {
          commit: {
            commit_hash: "abc123def456",
            message: "Add user authentication",
            summary: "Implemented JWT-based authentication system",
            repository_url: "https://github.com/user/repo"
          }
        }
      end

      it "creates a new commit" do
        expect {
          post "/api/v1/commits", params: valid_params, headers: headers, as: :json
        }.to change(Commit, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json_response['commit_hash']).to eq('abc123def456')
        expect(json_response['message']).to eq('Add user authentication')
        expect(json_response['summary']).to eq('Implemented JWT-based authentication system')
      end

      it "associates the commit with the authenticated user" do
        post "/api/v1/commits", params: valid_params, headers: headers, as: :json

        expect(Commit.last.user).to eq(user)
      end

      it "creates repository if it doesn't exist" do
        expect {
          post "/api/v1/commits", params: valid_params, headers: headers, as: :json
        }.to change(Repository, :count).by(1)

        expect(Commit.last.repository.url).to eq("https://github.com/user/repo")
      end

      it "uses existing repository if it already exists" do
        existing_repo = create(:repository, user: user, url: "https://github.com/user/repo")

        expect {
          post "/api/v1/commits", params: valid_params, headers: headers, as: :json
        }.to change(Repository, :count).by(0)

        expect(Commit.last.repository).to eq(existing_repo)
      end
    end

    context "with invalid authentication" do
      it "returns unauthorized without token" do
        post "/api/v1/commits", params: {}, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_response['error']).to eq('Unauthorized')
      end

      it "returns unauthorized with invalid token" do
        invalid_headers = { "Authorization" => "Bearer invalid_token" }
        post "/api/v1/commits", params: {}, headers: invalid_headers, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid params" do
      it "returns errors when commit_hash is missing" do
        invalid_params = {
          commit: {
            message: "Add user authentication",
            summary: "Implemented JWT-based authentication system",
            repository_url: "https://github.com/user/repo"
          }
        }

        post "/api/v1/commits", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['errors']).to be_present
      end
    end
  end

  describe "GET /api/v1/commits" do
    context "with valid authentication" do
      let(:repo) { create(:repository, user: user) }

      before do
        create(:commit, user: user, repository: repo, commit_hash: "abc123", message: "First commit", summary: "Summary 1")
        create(:commit, user: user, repository: repo, commit_hash: "def456", message: "Second commit", summary: "Summary 2")
      end

      it "returns all commits for the authenticated user" do
        get "/api/v1/commits", headers: headers

        expect(response).to have_http_status(:success)
        expect(json_response.length).to eq(2)
      end

      it "returns commits in descending order" do
        get "/api/v1/commits", headers: headers

        expect(json_response.first['commit_hash']).to eq('def456')
        expect(json_response.last['commit_hash']).to eq('abc123')
      end

      it "does not return other users' commits" do
        other_user = create(:user, email_address: "other@example.com")
        other_repo = create(:repository, user: other_user)
        create(:commit, user: other_user, repository: other_repo, commit_hash: "xyz789", message: "Other commit", summary: "Other summary")

        get "/api/v1/commits", headers: headers

        expect(json_response.length).to eq(2)
        expect(json_response.map { |c| c['commit_hash'] }).not_to include('xyz789')
      end
    end

    context "with invalid authentication" do
      it "returns unauthorized" do
        get "/api/v1/commits"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "DELETE /api/v1/commits/:id" do
    let!(:commit) { create(:commit, user: user, commit_hash: "abc123", message: "Test commit", summary: "Summary") }

    context "with valid authentication" do
      it "deletes the specified commit" do
        expect {
          delete "/api/v1/commits/#{commit.id}", headers: headers
        }.to change { user.commits.count }.by(-1)

        expect(response).to have_http_status(:ok)
        expect(json_response['message']).to eq('Commit deleted successfully')
      end

      it "returns not found for non-existent commit" do
        delete "/api/v1/commits/99999", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it "does not allow deleting other users' commits" do
        other_user = create(:user, email_address: "other@example.com")
        other_repo = create(:repository, user: other_user)
        other_commit = create(:commit, user: other_user, repository: other_repo, commit_hash: "xyz789", message: "Other commit", summary: "Other summary")

        delete "/api/v1/commits/#{other_commit.id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(other_commit.reload).to be_present
      end
    end

    context "with invalid authentication" do
      it "returns unauthorized" do
        delete "/api/v1/commits/#{commit.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
