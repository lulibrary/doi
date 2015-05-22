class AddDoiNameToResourceTypes < ActiveRecord::Migration
  def change
    add_column :resource_types, :doi_name, :string
  end
end
