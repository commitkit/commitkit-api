class AddRepositoryUrlToCommits < ActiveRecord::Migration[8.1]
  def change
    add_column :commits, :repository_url, :string
  end
end
