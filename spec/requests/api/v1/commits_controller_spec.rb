require "rails_helper"

RSpec.describe Api::V1::CommitsController, type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }

  describe "POST /api/v1/commits/batch" do
    context "with valid commits" do
      it "creates multiple commits and returns summary" do
        commits_data = [
          {
            commit_hash: "abc123",
            message: "First commit",
            author_name: "Test User",
            author_email: "test@example.com",
            committed_at: "2024-11-03T10:00:00Z"
          },
          {
            commit_hash: "def456",
            message: "Second commit",
            author_name: "Test User",
            author_email: "test@example.com",
            committed_at: "2024-11-03T11:00:00Z"
          }
        ]

        expect {
          post "/api/v1/commits/batch",
            params: { commits: commits_data },
            headers: headers,
            as: :json
        }.to change(Commit, :count).by(2)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["synced"]).to eq(2)
        expect(json["skipped"]).to eq(0)
        expect(json["failed"]).to eq(0)
      end
    end

    context "with duplicate commits" do
      it "skips already existing commits" do
        # Create one commit first
        create(:commit, user: user, commit_hash: "abc123")

        commits_data = [
          {
            commit_hash: "abc123",  # Duplicate
            message: "First commit",
            author_name: "Test User",
            author_email: "test@example.com",
            committed_at: "2024-11-03T10:00:00Z"
          },
          {
            commit_hash: "def456",  # New
            message: "Second commit",
            author_name: "Test User",
            author_email: "test@example.com",
            committed_at: "2024-11-03T11:00:00Z"
          }
        ]

        expect {
          post "/api/v1/commits/batch",
            params: { commits: commits_data },
            headers: headers,
            as: :json
        }.to change(Commit, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["synced"]).to eq(1)
        expect(json["skipped"]).to eq(1)
        expect(json["failed"]).to eq(0)
      end
    end

    context "with empty batch" do
      it "returns zero counts" do
        post "/api/v1/commits/batch",
          params: { commits: [] },
          headers: headers,
          as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["synced"]).to eq(0)
        expect(json["skipped"]).to eq(0)
        expect(json["failed"]).to eq(0)
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/v1/commits/batch",
          params: { commits: [] },
          as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid commit data" do
      it "tracks failed commits" do
        commits_data = [
          {
            commit_hash: "abc123",
            message: "Valid commit",
            author_name: "Test User",
            author_email: "test@example.com",
            committed_at: "2024-11-03T10:00:00Z"
          },
          {
            # Missing required commit_hash
            message: "Invalid commit",
            author_name: "Test User",
            author_email: "test@example.com",
            committed_at: "2024-11-03T11:00:00Z"
          }
        ]

        expect {
          post "/api/v1/commits/batch",
            params: { commits: commits_data },
            headers: headers,
            as: :json
        }.to change(Commit, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["synced"]).to eq(1)
        expect(json["skipped"]).to eq(0)
        expect(json["failed"]).to eq(1)
      end

      it "includes error details for failed commits" do
        commits_data = [
          {
            commit_hash: "abc123",
            message: "Valid commit"
          },
          {
            # Missing required commit_hash
            message: "Invalid commit"
          }
        ]

        post "/api/v1/commits/batch",
          params: { commits: commits_data },
          headers: headers,
          as: :json

        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
        expect(json["errors"].length).to eq(1)

        error = json["errors"].first
        expect(error["commit_hash"]).to be_nil
        expect(error["errors"]).to be_an(Array)
        expect(error["errors"]).not_to be_empty
      end
    end
  end
end
