class AddAiSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ai_summaries_enabled, :boolean, default: true, null: false
  end
end
