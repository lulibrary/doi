class ChangeDatatypeOnTableFromStringToText < ActiveRecord::Migration
  def up
    change_column :records, :title, :text, :limit => nil
  end

  def down
    change_column :records, :title, :string
  end
end
