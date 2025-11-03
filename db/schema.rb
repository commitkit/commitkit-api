# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_11_03_170206) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "commits", force: :cascade do |t|
    t.datetime "ai_generated_at"
    t.string "ai_model"
    t.string "ai_processing_status", default: "pending"
    t.string "ai_provider"
    t.text "ai_summary"
    t.string "commit_hash", null: false
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.text "message"
    t.bigint "repository_id", null: false
    t.string "repository_url"
    t.text "summary"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["ai_processing_status"], name: "index_commits_on_ai_processing_status"
    t.index ["commit_hash"], name: "index_commits_on_commit_hash", unique: true
    t.index ["committed_at"], name: "index_commits_on_committed_at"
    t.index ["repository_id"], name: "index_commits_on_repository_id"
    t.index ["user_id", "ai_processing_status"], name: "index_commits_on_user_id_and_ai_processing_status"
    t.index ["user_id", "commit_hash"], name: "index_commits_on_user_id_and_commit_hash", unique: true
    t.index ["user_id"], name: "index_commits_on_user_id"
  end

  create_table "repositories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "url"], name: "index_repositories_on_user_id_and_url", unique: true
    t.index ["user_id"], name: "index_repositories_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "ai_summaries_enabled", default: true, null: false
    t.string "api_token"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "commits", "repositories"
  add_foreign_key "commits", "users"
  add_foreign_key "repositories", "users"
  add_foreign_key "sessions", "users"
end
