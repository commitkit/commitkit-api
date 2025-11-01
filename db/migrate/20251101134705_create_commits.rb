class CreateCommits < ActiveRecord::Migration[8.1]
  def change
    create_table :commits do |t|
      t.references :user, null: false, foreign_key: true
      t.string :commit_hash, null: false
      t.text :message
      t.text :summary

      t.timestamps
    end

    add_index :commits, :commit_hash, unique: true
    add_index :commits, [ :user_id, :commit_hash ], unique: true
  end
end
