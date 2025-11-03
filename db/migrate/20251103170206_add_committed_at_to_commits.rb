class AddCommittedAtToCommits < ActiveRecord::Migration[8.1]
  def change
    add_column :commits, :committed_at, :datetime
    add_index :commits, :committed_at
  end
end
