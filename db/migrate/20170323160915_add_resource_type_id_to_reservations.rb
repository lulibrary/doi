class AddResourceTypeIdToReservations < ActiveRecord::Migration
  def change
    add_column :reservations, :resource_type_id, :integer
  end
end
