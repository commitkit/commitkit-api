class AddNameToRepositories < ActiveRecord::Migration[8.1]
  def change
    add_column :repositories, :name, :string
  end
end
