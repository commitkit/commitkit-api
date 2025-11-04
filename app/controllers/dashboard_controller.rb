class DashboardController < ApplicationController
  def index
    @repositories = Current.user.repositories.order(:name, :url)
    @total_commits = Current.user.commits.count

    # For CV Builder tab: ALL commits with AI summaries (no pagination)
    @commits_with_ai = Current.user.commits
                                   .where.not(ai_summary: nil)
                                   .order(created_at: :desc)

    # For All Commits tab: paginated commits (optionally filtered by repository)
    commits_scope = Current.user.commits
    commits_scope = commits_scope.where(repository_id: params[:repository_id]) if params[:repository_id].present?
    @pagy, @all_commits = pagy(commits_scope.order(created_at: :desc))
  end
end
