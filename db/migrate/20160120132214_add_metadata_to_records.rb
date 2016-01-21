class AddMetadataToRecords < ActiveRecord::Migration
  def change
    add_column :records, :metadata, :text
  end
end
