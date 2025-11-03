class Api::V1::CommitsController < Api::V1::BaseController
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

  def batch
    synced = 0
    skipped = 0
    failed = 0
    errors = []

    commits_params = params[:commits] || []
    commits_params.each do |commit_data|
      begin
        # Skip if already exists
        if current_user.commits.exists?(commit_hash: commit_data[:commit_hash])
          skipped += 1
          next
        end

        # Try to create
        commit = current_user.commits.new(
          commit_hash: commit_data[:commit_hash],
          message: commit_data[:message],
          summary: "Summary"
        )

        if commit.save
          synced += 1
        else
          failed += 1
          errors << {
            commit_hash: commit_data[:commit_hash],
            errors: commit.errors.full_messages
          }
        end
      rescue => e
        failed += 1
        errors << {
          commit_hash: commit_data[:commit_hash],
          errors: [ e.message ]
        }
      end
    end

    result = { synced: synced, skipped: skipped, failed: failed }
    result[:errors] = errors if errors.any?

    render json: result, status: :created
  end

  def destroy
    commit = current_user.commits.find_by(id: params[:id])

    if commit
      commit.destroy
      render json: { message: 'Commit deleted successfully' }, status: :ok
    else
      render json: { error: 'Commit not found' }, status: :not_found
    end
  end

  private

  def commit_params
    params.require(:commit).permit(:commit_hash, :message, :summary)
  end
end
