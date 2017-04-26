# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20170426092212) do

  create_table "doi_registration_agents", force: :cascade do |t|
    t.string  "name",  limit: 255
    t.integer "count"
  end

  create_table "records", force: :cascade do |t|
    t.integer  "pure_id"
    t.text     "title"
    t.string   "creator_name",              limit: 255
    t.string   "doi",                       limit: 255
    t.datetime "doi_created_at"
    t.string   "doi_created_by",            limit: 255
    t.text     "url"
    t.datetime "url_updated_at"
    t.string   "url_updated_by",            limit: 255
    t.datetime "metadata_updated_at"
    t.string   "metadata_updated_by",       limit: 255
    t.integer  "doi_registration_agent_id"
    t.integer  "resource_type_id"
    t.string   "pure_uuid",                 limit: 255
    t.text     "metadata"
  end

  create_table "reservations", force: :cascade do |t|
    t.integer  "pure_id"
    t.string   "doi",              limit: 255
    t.datetime "created_at"
    t.string   "created_by",       limit: 255
    t.integer  "resource_type_id"
  end

  create_table "resource_types", force: :cascade do |t|
    t.string  "name",     limit: 255
    t.string  "doi_name", limit: 255
    t.integer "count"
    t.string  "url_name"
  end

end
