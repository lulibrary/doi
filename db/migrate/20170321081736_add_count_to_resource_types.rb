class AddCountToResourceTypes < ActiveRecord::Migration
  def change
    add_column :resource_types, :count, :integer
  end
end
