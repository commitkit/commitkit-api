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

      context "with optional AI fields" do
        let(:params_with_ai) do
          {
            commit: {
              commit_hash: "abc123def456",
              message: "Add user authentication",
              repository_url: "https://github.com/user/repo",
              ai_summary: "Implemented secure authentication system with JWT tokens",
              ai_provider: "ollama",
              ai_model: "qwen2.5:14b",
              ai_generated_at: "2024-11-04T10:00:00Z"
            }
          }
        end

        it "accepts AI fields when provided" do
          post "/api/v1/commits", params: params_with_ai, headers: headers, as: :json

          expect(response).to have_http_status(:created)
          commit = Commit.last
          expect(commit.ai_summary).to eq("Implemented secure authentication system with JWT tokens")
          expect(commit.ai_provider).to eq("ollama")
          expect(commit.ai_model).to eq("qwen2.5:14b")
          expect(commit.ai_generated_at).to be_present
        end

        it "sets ai_processing_status to completed when AI fields provided" do
          post "/api/v1/commits", params: params_with_ai, headers: headers, as: :json

          expect(Commit.last.ai_processing_status).to eq("completed")
        end

        it "does not enqueue AI generation job when AI fields provided" do
          expect(GenerateAiSummaryJob).not_to receive(:perform_later)

          post "/api/v1/commits", params: params_with_ai, headers: headers, as: :json
        end
      end

      context "without optional AI fields" do
        it "sets ai_processing_status to pending by default" do
          post "/api/v1/commits", params: valid_params, headers: headers, as: :json

          expect(Commit.last.ai_processing_status).to eq("pending")
        end

        it "enqueues AI generation job when AI fields not provided" do
          allow(user).to receive(:ai_summaries_enabled?).and_return(true)
          expect(GenerateAiSummaryJob).to receive(:perform_later)

          post "/api/v1/commits", params: valid_params, headers: headers, as: :json
        end
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
