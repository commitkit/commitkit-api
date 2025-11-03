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
      render json: { message: "Commit deleted successfully" }, status: :ok
    else
      render json: { error: "Commit not found" }, status: :not_found
    end
  end

  # POST /api/v1/commits/generate_cv_bullets
  # Generates professional CV/resume bullet points from selected commits
  def generate_cv_bullets
    commit_ids = params[:commit_ids]
    context = params[:context] # Optional additional context from user

    unless commit_ids.present? && commit_ids.is_a?(Array)
      return render json: { error: "commit_ids must be an array" }, status: :unprocessable_entity
    end

    commits = current_user.commits.where(id: commit_ids).order(committed_at: :desc, created_at: :desc)

    if commits.empty?
      return render json: { error: "No commits found with provided IDs" }, status: :not_found
    end

    begin
      bullets = LlmService.generate_cv_bullets(commits: commits, context: context)
      render json: {
        bullets: bullets,
        commits_used: commits.count,
        generated_at: Time.current
      }, status: :ok
    rescue LlmService::LlmError => e
      Rails.logger.error("CV bullet generation failed: #{e.message}")
      render json: { error: "Failed to generate CV bullets: #{e.message}" }, status: :service_unavailable
    end
  end

  private

  def commit_params
    params.require(:commit).permit(:commit_hash, :message, :summary)
  end
end
