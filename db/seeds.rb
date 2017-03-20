# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)



# DoiRegistrationAgent

# comma separated list, append new ones
doi_registration_agent_list = ['DataCite']

doi_registration_agent_list.each do |name|
  r = DoiRegistrationAgent.create(name: name)
  r.count = 0
  r.save!
end



# ResourceType

ResourceType.create(name: 'Dataset', doi_name: 'researchdata')
ResourceType.create(name: 'Doctoral Thesis', doi_name: 'thesis')
ResourceType.create(name: "Master's Thesis", doi_name: 'thesis')