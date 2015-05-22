require 'rubygems'
require 'state_machine'

class DoiCreateStateMachine

  state_machine :state, initial: :awaiting_doi_remote_minting_verification do

    event :doi_minted do
      transition :awaiting_doi_remote_minting_verification => :already_minted
    end

    event :doi_not_minted do
      transition :awaiting_doi_remote_minting_verification => :creating_metadata
    end

    event :metadata_created do
      transition :creating_metadata => :creating_doi
    end

    event :doi_created do
      transition :creating_doi => :minted
    end

    state :awaiting_doi_remote_minting_verification
    state :already_minted
    state :creating_metadata
    state :creating_doi
    state :minted

  end

end