class AddPureUuidToRecords < ActiveRecord::Migration
  def change
    add_column :records, :pure_uuid, :string
  end
end
