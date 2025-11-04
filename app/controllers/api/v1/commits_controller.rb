class Api::V1::CommitsController < Api::V1::BaseController
  def index
    commits = current_user.commits.order(created_at: :desc)
    render json: commits
  end

  def create
    repository = current_user.repositories.find_or_create_by!(url: params[:commit][:repository_url])

    commit_attrs = {
      commit_hash: params[:commit][:commit_hash],
      message: params[:commit][:message],
      summary: params[:commit][:summary],
      committed_at: params[:commit][:committed_at],
      repository: repository
    }

    # Add optional AI fields if provided
    if params[:commit][:ai_summary].present?
      commit_attrs.merge!(
        ai_summary: params[:commit][:ai_summary],
        ai_provider: params[:commit][:ai_provider],
        ai_model: params[:commit][:ai_model],
        ai_generated_at: params[:commit][:ai_generated_at],
        ai_processing_status: "completed"
      )
    end

    commit = current_user.commits.new(commit_attrs)

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

  # POST /api/v1/commits/generate_ai_summaries
  # Batch generates AI summaries for commits without them
  def generate_ai_summaries
    commits_without_summaries = current_user.commits.where(ai_summary: nil)

    if commits_without_summaries.empty?
      return render json: {
        message: "All commits already have AI summaries",
        processed: 0
      }, status: :ok
    end

    # Process in background job for better UX (we'll implement this next)
    # For now, process synchronously but limit to prevent timeouts
    limit = params[:limit]&.to_i || 10
    commits_to_process = commits_without_summaries.limit(limit)

    processed = 0
    failed = 0

    commits_to_process.each do |commit|
      begin
        summary = LlmService.generate_commit_summary(message: commit.message)
        commit.update!(
          ai_summary: summary,
          ai_processing_status: "completed",
          ai_generated_at: Time.current,
          ai_model: LlmService::DEFAULT_MODEL
        )
        processed += 1
      rescue StandardError => e
        Rails.logger.error("Failed to generate summary for commit #{commit.id}: #{e.message}")
        commit.update(ai_processing_status: "failed")
        failed += 1
      end
    end

    remaining = commits_without_summaries.count - processed - failed

    render json: {
      processed: processed,
      failed: failed,
      remaining: remaining,
      message: "Generated #{processed} AI summaries"
    }, status: :ok
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
    params.require(:commit).permit(:commit_hash, :message, :summary, :committed_at)
  end
end
