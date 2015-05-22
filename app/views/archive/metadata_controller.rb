require 'nokogiri'

class MetadataController < ApplicationController

  def new
    @doi = params[:doi]
  end

  def create
    endpoint = ENV['ENDPOINT'] + '/metadata'
    username = ENV['USERNAME']
    password = ENV['PASSWORD']
    pem = File.read(ENV['PEM'])
    @xml = build_xml
    @doi = params[:doi]
    response_code = update_remote_metadata(endpoint, build_xml, username, password, pem)
    @status = response_status_message(response_code)
  end

  private

  def response_status_message(code)
    statuses = {
        '201' => 'Created - operation successful',
        '400' => 'Bad Request - invalid XML, wrong prefix',
        '401' => 'Unauthorized - no login',
        '403' => 'Forbidden - login problem, quota exceeded',
        '500' => 'Internal Server Error - server internal error, try later'
    }
    statuses[code]
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
            xml.creator {
              xml.creatorName_ creatorName
            }
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
    # xml = ''
    # xml += declaration
    # xml += root_open
    # xml += identifier_open
    # xml += params[:doi]
    # xml += identifier_close
    # xml += root_close
  # <creators>
  #   <creator>
  #     <creatorName>Khokhar, Masud</creatorName>
  #   </creator>
  #   <creator>
  #     <creatorName>Hartland, Andy</creatorName>
  #   </creator>
  # </creators>
  #   <titles>
  #   <title>Library staff page of Masud Khokhar</title>
  # </titles>
  #   <publisher>Lancaster University Library</publisher>
  # <publicationYear>2014</publicationYear>
  #   <subjects>
  #   <subject>Library</subject>
  #   <subject>Staff</subject>
  #   </subjects>
  # <language>eng</language>
  #   <resourceType resourceTypeGeneral="Dataset">Dataset</resourceType>
  # <version>1</version>
  #   <descriptions>
  #   <description descriptionType="Abstract">Masud is brilliant</description>
  # </descriptions>

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
    # @response = response
    @debug = true
    if @debug
      @response_class = response.class
      @headers = {}
      @headers[:request] = headers(req)
      @headers[:response] = headers(response)
    end
    response.code
    if response.code != '201'
      redirect_to :back, :flash => { :error => response.code + ' ' + response.body }
      return
    end
    redirect_to :back, :flash => { :notice => params[:doi] + ' metadata successfully updated' }

    now = DateTime.now
    record = Record.find(BLA)
    record.metadata_updated_at = now
    record.metadata_updated_by = set_user
    record.save
  end

  def headers(r)
    headers_hash = {}
    # headers_arr = []
    r.each_header do |header_name, header_value|
      # headers_arr << "HEADER #{header_name} : #{header_value}"
      headers_hash[header_name] = header_value
    end
    # headers_str = headers_arr.join(' ')
    headers_hash
  end

  def set_user
    # not available via WEBrick
    request.remote_user
  end

end