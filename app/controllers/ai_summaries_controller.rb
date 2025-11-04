class AiSummariesController < ApplicationController
  # POST /ai_summaries
  # Enqueues background jobs to generate AI summaries for commits without them
  def create
    commits_without_summaries = Current.user.commits.where(ai_summary: nil)

    if commits_without_summaries.empty?
      return render json: {
        message: "All commits already have AI summaries",
        enqueued: 0,
        total: 0
      }, status: :ok
    end

    # Enqueue all commits for background processing
    enqueued = 0
    commits_without_summaries.each do |commit|
      # Skip if already processing
      next if commit.ai_processing_status == "processing"

      GenerateAiSummaryJob.perform_later(commit.id)
      commit.update(ai_processing_status: "processing")
      enqueued += 1
    end

    render json: {
      enqueued: enqueued,
      total: commits_without_summaries.count,
      message: "Enqueued #{enqueued} commits for AI summary generation"
    }, status: :ok
  end
end
