class Record < ActiveRecord::Base
  belongs_to :doi_registration_agent
  belongs_to :resource_type
end