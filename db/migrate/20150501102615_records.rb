class Records < ActiveRecord::Migration
  def change
    create_table :records do |t|
      t.integer   :pure_id
      t.string    :title
      t.string    :creator_name
      t.string    :doi
      t.datetime  :doi_created_at
      t.string    :doi_created_by
      t.string    :url
      t.datetime  :url_updated_at
      t.string    :url_updated_by
      t.datetime  :metadata_updated_at
      t.string    :metadata_updated_by
      t.integer   :doi_registration_agent_id
      t.integer   :resource_type_id
    end
  end
end
