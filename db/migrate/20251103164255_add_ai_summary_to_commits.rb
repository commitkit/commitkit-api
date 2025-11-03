class AddAiSummaryToCommits < ActiveRecord::Migration[8.1]
  def change
    add_column :commits, :ai_summary, :text
    add_column :commits, :ai_provider, :string
    add_column :commits, :ai_model, :string
    add_column :commits, :ai_generated_at, :datetime
    add_column :commits, :ai_processing_status, :string, default: "pending"

    add_index :commits, :ai_processing_status
    add_index :commits, [:user_id, :ai_processing_status]
  end
end
