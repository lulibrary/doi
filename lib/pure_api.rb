module PureApi

  private

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

end