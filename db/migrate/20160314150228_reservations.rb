class Reservations < ActiveRecord::Migration
  def change
    create_table :reservations do |t|
      t.integer   :pure_id
      t.string    :doi
      t.datetime  :created_at
      t.string    :created_by
    end
  end
end
