class Commit < ApplicationRecord
  belongs_to :user
  belongs_to :repository

  validates :commit_hash, presence: true, uniqueness: true
  validates :message, presence: true

  after_create :enqueue_ai_summary_generation

  # Scopes for AI processing status
  scope :pending_ai_summary, -> { where(ai_processing_status: "pending") }
  scope :processing_ai_summary, -> { where(ai_processing_status: "processing") }
  scope :completed_ai_summary, -> { where(ai_processing_status: "completed") }
  scope :failed_ai_summary, -> { where(ai_processing_status: "failed") }

  private

  def enqueue_ai_summary_generation
    return unless user.ai_summaries_enabled?

    GenerateAiSummaryJob.perform_later(id)
  end
end
