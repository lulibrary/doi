class DoiRegistrationAgents < ActiveRecord::Migration
  def change
    create_table :doi_registration_agents do |t|
      t.string   :name
    end
  end
end