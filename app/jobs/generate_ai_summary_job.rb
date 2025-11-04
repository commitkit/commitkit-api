# frozen_string_literal: true

# Background job to generate AI summaries for commits
class GenerateAiSummaryJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(commit_id)
    commit = Commit.find(commit_id)
    return if commit.ai_processing_status == "completed"

    commit.update!(ai_processing_status: "processing")

    summary = LlmService.generate_commit_summary(message: commit.message)

    commit.update!(
      ai_summary: summary,
      ai_provider: :anthropic,
      ai_model: LlmService::DEFAULT_MODEL,
      ai_generated_at: Time.current,
      ai_processing_status: "completed"
    )

    Rails.logger.info("Generated AI summary for commit #{commit.id}")
  rescue LlmService::LlmError => e
    commit.update!(ai_processing_status: "failed")
    Rails.logger.error("AI summary generation failed for commit #{commit.id}: #{e.message}")
    raise  # Allow retry
  rescue StandardError => e
    commit.update!(ai_processing_status: "failed")
    Rails.logger.error("Unexpected error generating AI summary for commit #{commit.id}: #{e.message}")
    # Don't raise - we don't want to retry unexpected errors indefinitely
  end
end
