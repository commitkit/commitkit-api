class CreateRepositories < ActiveRecord::Migration[8.1]
  def change
    create_table :repositories do |t|
      t.string :url, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :repositories, [:user_id, :url], unique: true
  end
end
