class ChangeUrlDatatypeInRecordsFromStringToText < ActiveRecord::Migration
  def up
    change_column :records, :url, :text, :limit => nil
  end

  def down
    change_column :records, :url, :string
  end
end
