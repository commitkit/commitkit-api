class DashboardController < ApplicationController
  def index
    @repositories = Current.user.repositories.order(:name, :url)

    commits_scope = Current.user.commits
    commits_scope = commits_scope.where(repository_id: params[:repository_id]) if params[:repository_id].present?

    @commits = commits_scope.order(created_at: :desc).limit(50)
    @total_commits = Current.user.commits.count
  end
end
