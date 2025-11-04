class AddDiffFieldsToCommits < ActiveRecord::Migration[7.0]
  def change
    add_column :commits, :diff, :text
    add_column :commits, :diff_lines, :integer
    add_column :commits, :diff_size, :integer
    add_column :commits, :diff_too_large, :boolean, default: false
    add_column :commits, :default_branch, :string
  end
end
