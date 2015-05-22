class AddCountToDoiRegistrationAgents < ActiveRecord::Migration
  def change
    add_column :doi_registration_agents, :count, :integer
  end
end
