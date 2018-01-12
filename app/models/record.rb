class Record < ActiveRecord::Base
  include PgSearch
  pg_search_scope :search_stuff, against: [:metadata, :pure_uuid],
  using: {
      tsearch: {
          prefix: true,
          highlight: {
              start_sel: '<b>',
              stop_sel: '</b>',
          }
      }
  }

  belongs_to :doi_registration_agent
  belongs_to :resource_type
end