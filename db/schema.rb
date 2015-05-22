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

ActiveRecord::Schema.define(version: 20150519075221) do

  create_table "doi_registration_agents", force: true do |t|
    t.string  "name"
    t.integer "count"
  end

  create_table "records", force: true do |t|
    t.integer  "pure_id"
    t.string   "title"
    t.string   "creator_name"
    t.string   "doi"
    t.datetime "doi_created_at"
    t.string   "doi_created_by"
    t.string   "url"
    t.datetime "url_updated_at"
    t.string   "url_updated_by"
    t.datetime "metadata_updated_at"
    t.string   "metadata_updated_by"
    t.integer  "doi_registration_agent_id"
    t.integer  "resource_type_id"
  end

  create_table "resource_types", force: true do |t|
    t.string "name"
    t.string "doi_name"
  end

end
