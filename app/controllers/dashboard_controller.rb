class DashboardController < ApplicationController
  def index
    @repositories = Current.user.repositories.order(:name, :url)

    commits_scope = Current.user.commits
    commits_scope = commits_scope.where(repository_id: params[:repository_id]) if params[:repository_id].present?

    @pagy, @commits = pagy(commits_scope.order(created_at: :desc))
    @total_commits = Current.user.commits.count
  end
end
