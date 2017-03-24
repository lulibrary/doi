class AddUrlNameToResourceTypes < ActiveRecord::Migration
  def change
    add_column :resource_types, :url_name, :string
  end
end
