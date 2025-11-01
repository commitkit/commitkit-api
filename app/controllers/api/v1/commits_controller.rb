class Api::V1::CommitsController < ApplicationController
  include ApiAuthentication

  skip_before_action :verify_authenticity_token

  def index
    commits = current_user.commits.order(created_at: :desc)
    render json: commits
  end

  def create
    commit = current_user.commits.new(commit_params)

    if commit.save
      render json: commit, status: :created
    else
      render json: { errors: commit.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def commit_params
    params.require(:commit).permit(:commit_hash, :message, :summary)
  end
end
