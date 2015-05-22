require 'rubygems'
require 'state_machine'

class DoiFindStateMachine

  state_machine :state, initial: :awaiting_pure_verification do

    event :pure_dataset_found do
      transition :awaiting_pure_verification => :awaiting_doi_db_verification
    end

    event :pure_dataset_not_found do
      transition :awaiting_pure_verification => :awaiting_pure_verification
    end

    event :doi_db_record_found do
      transition :awaiting_doi_db_verification => :showing_doi
    end

    event :doi_db_record_not_found do
      transition :awaiting_doi_db_verification => :creating_doi
    end

    state :awaiting_doi_db_verification
    state :creating_doi
    state :showing_doi

  end

end