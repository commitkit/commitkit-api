class Api::V1::CommitsController < Api::V1::BaseController
  def index
    commits = current_user.commits.order(created_at: :desc)
    render json: commits
  end

  def create
    repository = current_user.repositories.find_or_create_by!(url: params[:commit][:repository_url])

    commit = current_user.commits.new(
      commit_hash: params[:commit][:commit_hash],
      message: params[:commit][:message],
      summary: params[:commit][:summary],
      repository: repository
    )

    if commit.save
      render json: commit, status: :created
    else
      render json: { errors: commit.errors.full_messages }, status: :unprocessable_entity
    end
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
