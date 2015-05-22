class ResourceTypes < ActiveRecord::Migration
  def change
    create_table :resource_types do |t|
      t.string   :name
    end
  end
end
