class DashboardController < ApplicationController
  def index
    @commits = Current.user.commits.order(created_at: :desc).limit(50)
    @total_commits = Current.user.commits.count
  end
end
