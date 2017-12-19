require 'uri'
require 'time'
require 'hash_to_html'
require 'research_metadata'
require 'puree'
require 'net/http'

class DoisController < ApplicationController
  include NetHttpHelper
  include Pure
  include PureApi
  # include CrosswalkPureToDatacite
  # include ResearchMetadata

  before_action :load_config

  def reservations
    reservation_summaries = []
    reservations = Reservation.all.order(created_at: :desc)
    reservations.each do |reservation|
      reservation_summary = {}
      reservation_summary['pure_id'] = reservation['pure_id']
      reservation_summary['doi'] = reservation['doi']
      reservation_summary['created_at'] = reservation['created_at']
      reservation_summary['created_by'] = reservation['created_by']
      if reservation.pure_id
        # fetch pure record

        # if dataset
        if reservation.resource_type_id === 1
          extractor = Puree::Extractor::Dataset.new @pure_config
        end

        # if thesis
        if reservation.resource_type_id === 2
          extractor = Puree::Extractor::Thesis.new @pure_config
        end

        metadata_model = extractor.find reservation.pure_id.to_s
        if metadata_model
          summary = pure_summary metadata_model
          reservation_summary['title'] = summary['title']
          reservation_summary['creator'] = summary['creator_name']
        end
      end
      reservation_summaries << reservation_summary
    end
    @reservation_summaries = reservation_summaries
  end

  def search
    @debug_endpoints = ENV['DEBUG_ENDPOINTS']
    @pure_up = pure_up?
    @datacite_up = datacite_up?
    @pure_version = pure_version
  end

  def find
    sm = DoiFindStateMachine.new

    pure_resource = determine_pure_resource_from_id params[:pure_id]
    metadata_model = pure_resource['model']

    if metadata_model
      sm.pure_dataset_found
      # logger.info 'Found ' + endpoint
      # logger.info params[:pure_id] +' has DOI ' + has_doi?(response.body).to_s
    else
      sm.pure_dataset_not_found
      # logger.info 'NOT Found ' + endpoint
    end

    if sm.state == 'awaiting_pure_verification'
      redirect_to :back,
                  :flash => { :error => 'Id not found in Pure' }
    end

    @records = Record.where("pure_id = ?", params[:pure_id])

    if @records.empty?
      sm.doi_db_record_not_found
    else
      sm.doi_db_record_found
    end

    @sm_state = sm.state

    if sm.state == 'showing_doi'
      # Using first result only, assuming only one doi for a given pure id
      redirect_to doi_path(id: @records.first.id)
    end

    if sm.state == 'creating_doi'
      summary = pure_summary metadata_model

      if !in_output_whitelist?(summary['output_type'])
        flash[:error] = "It is not possible to mint a DOI for an output of type #{summary['output_type']}"
        redirect_to :back
        return
      end

      summary['pure_id'] = params[:pure_id]
      redirect_to new_doi_path summary

    end

  end

  def index
    @records = Record.all.order(doi_created_at: :desc).paginate(:page => params[:page], :per_page => 10)
    if @records.empty?
      flash[:warning] = 'No records in database for DOIs'
    end
  end

  def new
    pure_id = params[:pure_id]
    if pure_id.empty?
      redirect_to :dois_search
    end
    #@display_prefixes = display_prefixes
    @reserved_doi = reserved_doi? pure_id
  end

  def edit
    @record = Record.find(params[:id])
    @metadata = get_db_metadata
    # @display_prefixes = display_prefixes
  end

  def show
    @record = Record.find(params[:id])
    @metadata = get_db_metadata
  end

  def get_db_metadata
    return JSON.parse(@record.metadata)["resource"]
  end

  def create
    sm = DoiCreateStateMachine.new

    # clean_doi_path = clean_doi_path(params[:doi])
    pure_id = params[:pure_id]
    output_type = params[:output_type]

    resource_type = get_resource output_type

    minting_from_reservation = false
    reservation = get_reservation(pure_id)
    doi = reservation ? reservation.doi : nil
    if doi
      minting_from_reservation = true
    end
    if !doi
      claim_reservation(pure_id, resource_type.id)
      reservation = get_reservation(pure_id)
      doi = reservation ? reservation.doi : nil
      if doi
        minting_from_reservation = true
      end
    end
    if !doi
      next_id = get_resource_type_next_id output_type

      doi_suffix = get_resource_type_doi_name output_type

      path = doi_suffix + '/' + next_id.to_s

      doi = build_doi(identifier: ENV['DATACITE_DOI_IDENTIFIER'],
                      prefix: ENV['DATACITE_DOI_PREFIX'], path: path)
    end
    url = build_url(params[:pure_uuid], params[:title], resource_type.id)

    resource = ENV['DATACITE_ENDPOINT'] + '/doi/' + doi
    username = ENV['DATACITE_USERNAME']
    password = ENV['DATACITE_PASSWORD']
    pem = File.read(ENV['PEM'])

    if remote_doi_minted?(resource, username, password, pem)
      sm.doi_minted
      # do nothing
      flash[:error] = doi + ' already minted'
    else
      sm.doi_not_minted
    end

    if sm.state == 'creating_metadata'
      result = create_metadata(doi)
      if result == 'success'
        sm.metadata_created
      else
        flash[:error] = result
      end
    end

    if sm.state == 'creating_doi'
      result = create_doi(doi, url)

      if result == 'success'
        sm.doi_created
        flash[:notice] = doi + ' minted with metadata'
      else
        flash[:error] = result
      end
    end

    if sm.state == 'minted'
      if minting_from_reservation
        delete_reserved_doi pure_id
      else
        increment_resource_type_count output_type
      end
    end

    if flash[:error]
      redirect_to :back
    end

    @sm_state = sm.state
  end

  def create_doi(doi, url)

    endpoint = ENV['DATACITE_ENDPOINT'] + ENV['DATACITE_RESOURCE_DOI']

    clean_url_path = strip_forward_slashes(url)

    url = clean_url_path

    username = ENV['DATACITE_USERNAME']
    password = ENV['DATACITE_PASSWORD']
    pem = File.read(ENV['PEM'])

    response = create_remote_doi(endpoint, doi, url, username, password, pem)

    if response.code != '201'
      return 'Datacite ' + response.code + ' ' + response.body
    end

    now = DateTime.now
    record = Record.find_or_create_by(doi: doi)
    record.doi_created_at = now
    record.doi_created_by = get_user
    record.url = url
    record.url_updated_at = now
    record.url_updated_by = get_user
    record.save

    return 'success'

  end

  def claim_reservation(pure_id, resource_type_id)
    reservation = get_cancelled_reservation
    if reservation
      # is the reservation for the same type of resource?
      if reservation.resource_type_id === resource_type_id
        reservation.pure_id = pure_id
        now = DateTime.now
        reservation.created_at = now
        reservation.created_by = get_user
        reservation.save
      end
    end
  end

  def reserve
    pure_id = params[:pure_id]
    output_type = params[:output_type]

    resource_type = get_resource output_type

    # is there an existing reservation?
    if !reserved_doi?(pure_id)
      # attempt to use a generated doi which has become available as a result
      # of a cancelled reservation
      claim_reservation(pure_id, resource_type.id)
    end

    # is there an existing reservation?
    if !reserved_doi?(pure_id)


      # create a new doi if there are none to recycle
      reservation = Reservation.create(pure_id: pure_id)

      next_id = get_resource_type_next_id output_type

      doi_suffix = get_resource_type_doi_name output_type

      path = doi_suffix + '/' + next_id.to_s

      doi = build_doi(identifier: ENV['DATACITE_DOI_IDENTIFIER'],
                      prefix: ENV['DATACITE_DOI_PREFIX'], path: path)

      reservation.doi = doi
      now = DateTime.now
      reservation.created_at = now
      reservation.created_by = get_user
      reservation.resource_type_id = resource_type.id

      if reservation.save
        increment_resource_type_count output_type
      end
    end

    redirect_to :root
  end

  def unreserve
    pure_id = params[:pure_id]
    reservation = Reservation.find_by(pure_id: pure_id)
    if reservation
      reservation.pure_id = nil
      now = DateTime.now
      reservation.created_at = now
      reservation.created_by = get_user
      reservation.save
    end

    redirect_to :root
  end

  # to reorganise
  def update
    edit_url_post(params[:id], params[:url])

  end

  def edit_url_post(id, url)
    edit_url(id, url: url, batch_mode: false)
  end

  def edit_url(id, url: '', batch_mode: false)

    success = false

    endpoint = ENV['DATACITE_ENDPOINT'] + ENV['DATACITE_RESOURCE_DOI']

    if !batch_mode
      clean_url_path = strip_forward_slashes(url)
      url = clean_url_path
    end

    record = Record.find(id)
    doi = record.doi
    current_url = record.url
    url_dirty = false

    if batch_mode
      resource_type = ResourceType.where(id: record.resource_type_id).first
      url = build_url(record.pure_uuid, record.title, resource_type.id)
    end

    if current_url != url
      url_dirty = true
    end

    if url_dirty
      username = ENV['DATACITE_USERNAME']
      password = ENV['DATACITE_PASSWORD']
      pem = File.read(ENV['PEM'])

      response = create_remote_doi(endpoint, doi, url, username, password, pem)
      if response.code != '201'
        if !batch_mode
          redirect_to :back,
                      :flash => { :error => response.code + ' ' + response.body }
        end
        return success
      end
      if !batch_mode
        redirect_to :root,
                    :doi => doi,
                    :flash => { :notice => doi + ' URL updated' }
      end
      success = true
      if success
        now = DateTime.now
        record.url = url
        record.url_updated_at = now
        if batch_mode
          user = 'batch'
        else
          user = get_user
        end
        record.url_updated_by = user
        record.save
      end
      return success
    else
      msg = ' URL unchanged - update skipped'
      logger.info doi + ' ' + msg
      if !batch_mode
        redirect_to :back,
                    :flash => { :warning => doi + msg }
      end
    end
  end

  def edit_metadata_post
    edit_metadata(params[:id])
  end

  def edit_metadata(id, batch_mode: false)

    success = false

    # LOCAL DB
    record = Record.find(id)

    pure_id = record.pure_id
    doi = record.doi

    # PURE
    resource_type = resource_type_from_resource_type_id record.resource_type_id

    transformer = nil
    if resource_type === 'Dataset'
      transformer = ResearchMetadata::Transformer::Dataset.new @pure_config
    elsif resource_type === 'Thesis'
      transformer = ResearchMetadata::Transformer::Thesis.new @pure_config
    end

    if transformer
      datacite_metadata = transformer.transform id: pure_id,
                                                doi: doi
    end

    if !datacite_metadata
      if !batch_mode
        redirect_to :back,
                    :flash => { :error => 'Error fetching data from Pure' }
      end
      return success
    end

    # is metadata dirty?
    metadata_dirty = false
    serialised_metadata = serialise_xml_to_json(datacite_metadata)
    if record.metadata != serialised_metadata
      metadata_dirty = true
    end

    if metadata_dirty
      # DATACITE
      endpoint = ENV['DATACITE_ENDPOINT'] + ENV['DATACITE_RESOURCE_METADATA']
      username = ENV['DATACITE_USERNAME']
      password = ENV['DATACITE_PASSWORD']
      pem = File.read(ENV['PEM'])
      response = update_remote_metadata(endpoint, datacite_metadata, username,
                                        password, pem)
      if response.code != '201'
        if !batch_mode
          redirect_to :back,
                      :flash => { :error => response.code + ' ' + response.body }
        end
        return success
      end
      if !batch_mode
        redirect_to :root,
                    :flash => { :notice => doi + ' metadata updated' }
      end
      success = true

      if success
        now = DateTime.now
        record.metadata_updated_at = now
        if batch_mode
          user = 'batch'
        else
          user = get_user
        end
        record.metadata_updated_by = user
        record.metadata = serialised_metadata
        record.save
      end
      return success
    else
      msg = ' Metadata unchanged - update skipped'
      logger.info pure_id.to_s + ', ' + msg
      if !batch_mode
        redirect_to :back,
                    :flash => { :warning => doi + msg }
      end
    end
  end

  def batch(batch_type, benchmark: true)
    load_config
    action = ''
    case batch_type
      when 'metadata'
        action = 'edit_metadata_batch'
      when 'url'
        action = 'edit_url_batch'
    end

    if action
      if benchmark
        logger.info Benchmark.measure{self.send(action)}
      else
        self.send(action)
      end
    end
  end

  def edit_metadata_batch
    logger.info ''
    logger.info ''
    logger.info 'Metadata batch update started.'
    logger.info 'Success?, Pure ID, Title'
    logger.info ''
    records = []
    successes = 0
    failures = 0
    Record.all.each do |record|
      data = {}
      data['record'] = record
      data['updated'] = edit_metadata(record.id, batch_mode: true)
      summary = data['record']['pure_id'].to_s + ', ' + data['record']['title']
      success = data['updated'] ? '1' : '0'
      data['updated'] ? successes+=1:failures+=1
      msg = success + ', ' + summary
      logger.info msg
      records << data
    end
    logger.info ''
    logger.info 'Metadata batch update finished.'
    logger.info 'Successes - ' + successes.to_s
    logger.info 'Failures  - ' + failures.to_s

    @data = records; nil   # suppress output
  end



  def edit_url_batch
    logger.info ''
    logger.info ''
    logger.info 'URL batch update started.'
    logger.info 'Success?, Pure ID, Title'
    logger.info ''
    records = []
    successes = 0
    failures = 0
    Record.all.each do |record|
      data = {}
      data['record'] = record
      data['updated'] = edit_url(record.id, batch_mode: true)
      summary = data['record']['pure_id'].to_s + ', ' + data['record']['title']
      success = data['updated'] ? '1' : '0'
      data['updated'] ? successes+=1:failures+=1
      msg = success + ', ' + summary
      logger.info msg
      records << data
    end
    logger.info ''
    logger.info 'URL batch update finished.'
    logger.info 'Successes - ' + successes.to_s
    logger.info 'Failures  - ' + failures.to_s

    @data = records; nil   # suppress output
  end

  def build_url(uuid, title, resource_type_id)
    url_name = get_resource_type_url_name resource_type_id
    return ENV['DATACITE_URL_PREFIX'] + url_name + '/' + slug_from_title(title) + '(' + uuid + ')' + '.html'
  end

  private

  def pure_up?
    HTTP.head(ENV['PURE_URL']).code === 401
  end

  def datacite_up?
    HTTP.head(ENV['DATACITE_ENDPOINT']).code === 200
  end

  def pure_version
    # server = Puree::Extractor::Server.new @pure_config
    # server.find.version
  end

  def remote_doi_minted?(resource, username, password, pem)
    uri = URI.parse(resource)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    # Next three lines work even when certificate has expired
    # so could be removed, along with pem parameter
    http.cert = OpenSSL::X509::Certificate.new(pem)
    http.key = OpenSSL::PKey::RSA.new(pem)
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    req = Net::HTTP::Get.new(uri)
    req.basic_auth username, password
    response = http.request(req)
    if response.code == '200'
      return true
    else
      return false
    end
  end

  def build_xml
    builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
      xml.resource( 'xmlns' => 'http://datacite.org/schema/kernel-3',
                    'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                    'xsi:schemaLocation' => 'http://datacite.org/schema/kernel-3 http://schema.datacite.org/meta/kernel-3/metadata.xsd'
      ) {
        xml.identifier params[:doi], :identifierType => 'DOI'
        xml.creators {
          params[:creatorName].each do |creatorName|
            if !creatorName.blank?
              xml.creator {
                xml.creatorName_ creatorName
              }
            end
          end
        }
        xml.titles {
          xml.title params[:title]
        }
        xml.publisher params[:publisher]
        xml.publicationYear params[:publicationYear]
      }
    end
    builder.to_xml
  end

  def create_remote_doi(endpoint, doi, url, username, password, pem)

    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.cert = OpenSSL::X509::Certificate.new(pem)
    http.key = OpenSSL::PKey::RSA.new(pem)
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    req = Net::HTTP::Post.new(uri)
    req.content_type = 'text/plain;charset=UTF-8'
    req.basic_auth username, password
    req.set_form_data({"doi" => doi, "url" => url})

    @headers = {}
    @headers[:request] = headers(req)

    response = http.request(req)
    @headers[:response] = headers(response)
    response
  end

  def get_remote_dois(resource, username, password, pem)
    uri = URI.parse(resource)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.cert = OpenSSL::X509::Certificate.new(pem)
    http.key = OpenSSL::PKey::RSA.new(pem)
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    req = Net::HTTP::Get.new(uri)
    req.basic_auth username, password
    response = http.request(req)
  end

  def build_doi(identifier: 'xx.yyyy', prefix: '', path: '')
    doi = identifier
    if prefix
      doi += '/' + prefix
    end
    if path
      doi += '/' + path
    end
  end

  # TO DO
  # Put this as lookup table in DB?
  def normalise_resource_name(output_type)
    return 1 if output_type === 'Dataset'

    thesis_types = ['Doctoral Thesis', "Master's Thesis"]
    return 2 if thesis_types.include? output_type

    return nil
  end

  def get_resource_type_next_id(output_type)
    resource_type_id = normalise_resource_name output_type
    resource_type = ResourceType.where(id: resource_type_id).first
    resource_type.count + 1
  end

  # def get_doi_registration_agent_next_id(doi_registration_agent_id)
  #   agent = DoiRegistrationAgent.find(doi_registration_agent_id)
  #   agent.count + 1
  # end

  def increment_resource_type_count(output_type)
    resource_type_id = normalise_resource_name output_type
    resource_type = ResourceType.where(id: resource_type_id).first
    resource_type.count += 1
    resource_type.save
  end

  # def increment_doi_registration_agent_count(doi_registration_agent_id)
  #   agent = DoiRegistrationAgent.find(doi_registration_agent_id)
  #   agent.count += 1
  #   agent.save
  # end

  def get_resource(output_type)
    resource_type_id = normalise_resource_name output_type
    ResourceType.where(id: resource_type_id).first
  end

  def get_resource_type_doi_name(output_type)
    resource_type_id = normalise_resource_name output_type
    resource_type = ResourceType.where(id: resource_type_id).first
    resource_type.doi_name
  end

  def get_resource_type_url_name(resource_type_id)
    resource_type = ResourceType.where(id: resource_type_id).first
    resource_type.url_name
  end



  # METADATA

  def create_metadata_transformer(output_type)
    transformer = nil
    if output_type === 'Dataset'
      transformer = ResearchMetadata::Transformer::Dataset.new @pure_config
    end
    research_output_whitelist = ['Doctoral Thesis', "Master's Thesis"]
    if research_output_whitelist.include? output_type
      transformer = ResearchMetadata::Transformer::Thesis.new @pure_config
    end
    transformer
  end

  def create_metadata(doi)
    transformer = create_metadata_transformer params[:output_type]
    datacite_metadata = transformer.transform id: params[:pure_id].to_s,
                                              doi: doi
    # DATACITE
    endpoint = ENV['DATACITE_ENDPOINT'] + ENV['DATACITE_RESOURCE_METADATA']
    username = ENV['DATACITE_USERNAME']
    password = ENV['DATACITE_PASSWORD']
    pem = File.read(ENV['PEM'])
    response = update_remote_metadata(endpoint, datacite_metadata, username,
                                      password, pem)
    if response.code != '201'
      return 'Datacite ' + response.code + ' ' + response.body
    end
    redirect_to :root,
                :flash => { :notice => doi + ' metadata updated' }

    agent_id = params[:record][:doi_registration_agent_id]

    # resource_type_id = params[:record][:resource_type_id]
    resource_type_id = normalise_resource_name params[:output_type]

    now = DateTime.now
    record = Record.new
    record.pure_id = params[:pure_id]
    record.title = params[:title]
    record.creator_name = params[:creator_name]
    record.doi = doi
    record.doi_created_at = now
    record.doi_created_by = get_user
    record.metadata_updated_at = now
    record.metadata_updated_by = get_user
    record.doi_registration_agent_id = agent_id
    record.resource_type_id = resource_type_id
    record.pure_uuid = params[:pure_uuid]
    record.metadata = serialise_xml_to_json(datacite_metadata)
    record.save

    return 'success'
  end

  def update_remote_metadata(endpoint, xml, username, password, pem)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.cert = OpenSSL::X509::Certificate.new(pem)
    http.key = OpenSSL::PKey::RSA.new(pem)
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    req = Net::HTTP::Post.new(uri)
    req.initialize_http_header({'Accept' => 'application/xml;charset=UTF-8'})
    req.content_type = 'application/xml;charset=UTF-8'
    req.basic_auth username, password
    req.body = xml
    response = http.request(req)
    @debug = false
    if @debug
      @response_class = response.class
      @headers = {}
      @headers[:request] = headers(req)
      @headers[:response] = headers(response)
    end
    response
  end

  # def get_remote_metadata_pure(endpoint, username, password, pem)
  #   return get_remote_metadata_pure_native(endpoint, username, password, pem)
  #   # get_remote_metadata_pure_local(endpoint, username, password, pem)
  # end
  #
  # def get_remote_metadata_pure_native(endpoint, username, password, pem)
  #   uri = URI.parse(endpoint)
  #   http = Net::HTTP.new(uri.host, uri.port)
  #   # http.use_ssl = true
  #   # http.cert = OpenSSL::X509::Certificate.new(pem)
  #   # http.key = OpenSSL::PKey::RSA.new(pem)
  #   # http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  #   req = Net::HTTP::Get.new(uri)
  #
  #   auth = Base64::encode64(username+':'+"#{password}")
  #   req.initialize_http_header({'Accept' => 'application/xml',
  #                               'Authorization' => 'Basic ' + auth
  #                              })
  #
  #   req.content_type = 'application/xml;charset=UTF-8'
  #
  #   response = http.request(req)
  #   @debug = false
  #   if @debug
  #     @response_class = response.class
  #     @headers = {}
  #     @headers[:request] = headers(req)
  #     @headers[:response] = headers(response)
  #   end
  #
  #   response
  #
  # end

  def serialise_xml_to_json(xml)
    Hash.from_xml(xml).to_json.to_s
  end

  def get_remote_metadata_pure_local(endpoint, username, password, pem)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.cert = OpenSSL::X509::Certificate.new(pem)
    http.key = OpenSSL::PKey::RSA.new(pem)
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    req = Net::HTTP::Get.new(uri)

    # Pure API does not use Basic word before base64 encoded string!
    # req.basic_auth username, password
    auth = Base64::encode64(username+':'+password)
    req.initialize_http_header({'Accept' => 'application/xml',
                                'Authorization' => auth})

    req.content_type = 'application/xml;charset=UTF-8'

    response = http.request(req)
    @debug = true
    if @debug
      @response_class = response.class
      @headers = {}
      @headers[:request] = headers(req)
      @headers[:response] = headers(response)
    end

    response

  end

  def pure_native_orcid(uuid)
    endpoint = ENV['PURE_URL'] + '/person?rendering=long&uuids.uuid=' + uuid

    username = ENV['PURE_USERNAME']
    password = ENV['PURE_PASSWORD']
    pem = File.read(ENV['PEM'])
    response = get_remote_metadata_pure(endpoint, username, password, pem)

    html = response.body

    doc = Nokogiri::HTML(html)
    orcid = doc.xpath("//table/tbody/tr[th='ORCID']/td").text
    if isORCID?(orcid)
      return orcid
    else
      return ''
    end
  end

  def isORCID?(str)
    if /^\d{4}-\d{4}-\d{4}-\d{4}$/.match(str)
      return true
    else
      return false
    end
  end

  def get_publication_from_uuid_pure_native(uuid)
    endpoint = ENV['PURE_URL'] + '/publication?rendering=xml_short&uuids.uuid=' + uuid

    username = ENV['PURE_USERNAME']
    password = ENV['PURE_PASSWORD']
    pem = File.read(ENV['PEM'])
    response = get_remote_metadata_pure(endpoint, username, password, pem)
  end

  def get_project_from_uuid_pure_native(uuid)
    # AS AT 2016-01-14 THERE IS NO SEMANTICALLY MEANINGFUL WAY TO INCLUDE THE RELATED PROJECT(S) IN THE METADATA
    # isDocumentedBy for a project url (stab1:projectURL) is the closest but inaccurate as it describes the project not the dataset
    endpoint = ENV['PURE_URL'] + '/project?rendering=xml_long&uuids.uuid=' + uuid

    username = ENV['PURE_USERNAME']
    password = ENV['PURE_PASSWORD']
    pem = File.read(ENV['PEM'])
    response = get_remote_metadata_pure(endpoint, username, password, pem)
  end

  # UTILS

  # def display_prefixes
  #   doi = ENV['DATACITE_DOI_IDENTIFIER']
  #   if !ENV['DATACITE_DOI_PREFIX'].blank?
  #     doi += '/' + ENV['DATACITE_DOI_PREFIX']
  #   end
  #   doi += '/'
  #   host = ENV['URL_HOST_1'] + '/'
  #   {
  #       :doi => doi,
  #       :url =>  host
  #   }
  # end

  # for making a random doi suffix for testing
  def token(length=16)
    chars = [*('A'..'Z'), *('a'..'z'), *(0..9)]
    (0..length).map {chars.sample}.join
  end

  def strip_forward_slashes(str)
    # multiple trailing slashes
    no_trailing = str.sub(/(\/)+$/,'')
    # multiple leading slashes
    no_trailing.sub(/^(\/)+/,'')
  end

  def strip_doi_identifier(str)
    doi = ENV['DOI_IDENTIFIER']
    str.sub(/(#{doi})+(\/)+/,'')
  end

  def strip_doi_prefix(str)
    prefix = ENV['DOI_PREFIX']
    str.sub(/(#{prefix})(\/)++/,'')
  end

  def clean_doi_path(str)
    a = strip_doi_identifier(str)
    b = strip_doi_prefix(a)
    c = strip_forward_slashes(b)
  end

  def mock_create_remote_doi(endpoint, doi)
    # https://test.datacite.org/mds/doi/10.4124/LANCASTER/
    endpoint + '/' + doi
  end

  def mock_db_query(pure_id)
    doi = 'XX.YYYY/WHATEVER'
    url = 'http://example.com/whatever'
    {
        'pure_id'             => pure_id,
        'doi'                 => doi,
        'url'                 => url,
        'doi_created'         => Time.now,
        'doi_modified'        => Time.now,
        'metadata_modified'   => Time.now
    }
  end

  def get_user
    # not available via WEBrick
    request.remote_user
  end

end

def reserved_doi?(pure_id)
  return Reservation.find_by(pure_id: pure_id) ? true : false
end

def delete_reserved_doi(pure_id)
  Reservation.find_by(pure_id: pure_id).delete
end

def get_cancelled_reservation
  return Reservation.where(pure_id: nil).first
end

def get_reservation(pure_id)
  Reservation.find_by(pure_id: pure_id)
end

def slug_from_title(title)
  slug = title
  # remove leading/trailing whitespace
  slug = slug.strip
  # make lowercase
  slug = slug.downcase
  # remove characters that are not 0-9,a-Z, or space
  slug = slug.gsub(/[^0-9a-z ]/i, '')
  # replace space between words with a dash
  slug = slug.gsub(/ /, '-')
end

def load_config
  @pure_config = {
      url:      ENV['PURE_URL'],
      username: ENV['PURE_USERNAME'],
      password: ENV['PURE_PASSWORD'],
      api_key:  ENV['PURE_API_KEY']
  }
end