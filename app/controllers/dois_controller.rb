require "uri"
require "time"

class DoisController < ApplicationController
  include NetHttpHelper
  include Pure
  include CrosswalkPureToDatacite

  def search
    @debug_endpoints = ENV['DEBUG_ENDPOINTS']
  end

  def find
    sm = DoiFindStateMachine.new

    # fetch pure record
    endpoint = ENV['PURE_ENDPOINT'] + '/datasets?rendering=xml_long&pureInternalIds.id=' + params[:pure_id]
    username = ENV['PURE_USERNAME']
    password = ENV['PURE_PASSWORD']
    pem = File.read(ENV['PEM'])
    response = get_remote_metadata_pure(endpoint, username, password, pem)
    # logger.info endpoint + ' ' + response.body

    if pure_dataset_exists?(response.body)
      sm.pure_dataset_found
      # logger.info 'Found ' + endpoint
      # logger.info params[:pure_id] +' has DOI ' + has_doi?(response.body).to_s
    else
      sm.pure_dataset_not_found
      # logger.info 'NOT Found ' + endpoint
    end

    if sm.state == 'awaiting_pure_verification'
      redirect_to :back,
                  :flash => { :error => 'Id not found for a dataset in Pure',
                              :pure_response => response.inspect
                  }
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
      summary = pure_dataset_summary(response.body)
      summary['pure_id'] = params[:pure_id]
      redirect_to new_doi_path(summary)
    end

  end

  def index
    @records = Record.all.order(doi_created_at: :desc).paginate(:page => params[:page], :per_page => 10)
    if @records.empty?
      flash[:warning] = 'No records in database for DOIs'
    end
  end

  def new
    if params[:pure_id].empty?
      redirect_to :dois_search
    end
    @display_prefixes = display_prefixes
  end

  def edit
    @record = Record.find(params[:id])
    # @display_prefixes = display_prefixes
  end

  def show
    @record = Record.find(params[:id])
  end

  def create
    sm = DoiCreateStateMachine.new

    # clean_doi_path = clean_doi_path(params[:doi])

    agent_id = params[:record][:doi_registration_agent_id]
    next_id = get_doi_registration_agent_next_id(agent_id)

    resource_type_id = params[:record][:resource_type_id]
    doi_suffix = get_resource_type_doi_name(resource_type_id)

    path = doi_suffix + '/' + next_id.to_s

    doi = build_doi(identifier: ENV['DATACITE_DOI_IDENTIFIER'],
                    prefix: ENV['DATACITE_DOI_PREFIX'], path: path)

    # url = params[:url]
    url = ENV['DATACITE_URL_PREFIX'] + '/' + doi_suffix + '-' + next_id.to_s
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

  def update
    endpoint = ENV['DATACITE_ENDPOINT'] + ENV['DATACITE_RESOURCE_DOI']

    doi = params[:doi] # No cleaning, as its from Datacite

    clean_url_path = strip_forward_slashes(params[:url])
    url = clean_url_path

    # url = params[:url]

    username = ENV['DATACITE_USERNAME']
    password = ENV['DATACITE_PASSWORD']
    pem = File.read(ENV['PEM'])

    response = create_remote_doi(endpoint, doi, url, username, password, pem)
    if response.code != '201'
      redirect_to :back,
                  :flash => { :error => response.code + ' ' + response.body }
      return
    end
    redirect_to :root,
                :doi => doi,
                :flash => { :notice => doi + ' URL updated' }

    now = DateTime.now
    record = Record.find(params[:id])
    record.url = url
    record.url_updated_at = now
    record.url_updated_by = get_user
    record.save
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
    endpoint = ENV['PURE_ENDPOINT'] + '/datasets?rendering=xml_long&pureInternalIds.id=' + pure_id.to_s
    username = ENV['PURE_USERNAME']
    password = ENV['PURE_PASSWORD']
    pem = File.read(ENV['PEM'])

    response = get_remote_metadata_pure(endpoint, username, password, pem)
    pure_native_dataset_exists = pure_dataset_exists?(response.body)
    if response.code != '200' or !pure_native_dataset_exists
      if !batch_mode
        redirect_to :back,
                    :flash => { :error => response.code + ' ' + response.body }
      end
      return success
    end
    metadata = response.body

    datacite_metadata = crosswalk_pure_to_datacite_dataset_metadata(doi,
                                                                     metadata)
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
      record.save
    end

    return success
  end

  # convenience method
  def batch
    edit_metadata_batch
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


  private



  def remote_doi_minted?(resource, username, password, pem)
    uri = URI.parse(resource)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
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

  def get_doi_registration_agent_next_id(doi_registration_agent_id)
    agent = DoiRegistrationAgent.find(doi_registration_agent_id)
    agent.count + 1
  end

  def increment_doi_registration_agent_count(doi_registration_agent_id)
    agent = DoiRegistrationAgent.find(doi_registration_agent_id)
    agent.count += 1
    agent.save
  end

  def get_resource_type_doi_name(resource_type_id)
    resource_type = ResourceType.find(resource_type_id)
    resource_type.doi_name
  end


  # METADATA

  def create_metadata(doi)
    # PURE
    endpoint = ENV['PURE_ENDPOINT'] + '/datasets?rendering=xml_long&pureInternalIds.id=' + params[:pure_id].to_s
    username = ENV['PURE_USERNAME']
    password = ENV['PURE_PASSWORD']
    pem = File.read(ENV['PEM'])
    response = get_remote_metadata_pure(endpoint, username, password, pem)

    if response.code != '200'
      return 'Pure ' + response.code + ' ' + response.body
    end
    metadata = response.body

    @datacite_metadata = crosswalk_pure_to_datacite_dataset_metadata(doi,
                                                                     metadata)

    # DATACITE
    endpoint = ENV['DATACITE_ENDPOINT'] + ENV['DATACITE_RESOURCE_METADATA']
    username = ENV['DATACITE_USERNAME']
    password = ENV['DATACITE_PASSWORD']
    pem = File.read(ENV['PEM'])
    response = update_remote_metadata(endpoint, @datacite_metadata, username,
                                      password, pem)
    if response.code != '201'
      return 'Datacite ' + response.code + ' ' + response.body
    end
    redirect_to :root,
                :flash => { :notice => doi + ' metadata updated' }

    agent_id = params[:record][:doi_registration_agent_id]
    resource_type_id = params[:record][:resource_type_id]

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
    record.save

    increment_doi_registration_agent_count(agent_id)

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

  def get_remote_metadata_pure(endpoint, username, password, pem)
    return get_remote_metadata_pure_native(endpoint, username, password, pem)
    # get_remote_metadata_pure_local(endpoint, username, password, pem)
  end

  def get_remote_metadata_pure_native(endpoint, username, password, pem)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    # http.use_ssl = true
    # http.cert = OpenSSL::X509::Certificate.new(pem)
    # http.key = OpenSSL::PKey::RSA.new(pem)
    # http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    req = Net::HTTP::Get.new(uri)

    auth = Base64::encode64(username+':'+"#{password}")
    req.initialize_http_header({'Accept' => 'application/xml',
                                'Authorization' => 'Basic ' + auth
                               })

    req.content_type = 'application/xml;charset=UTF-8'

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
    endpoint = ENV['PURE_ENDPOINT'] + '/person?rendering=long&uuids.uuid=' + uuid

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

