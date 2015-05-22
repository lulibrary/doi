module NetHttpHelper

  def headers(r)
    headers_hash = {}
    r.each_header do |header_name, header_value|
      headers_hash[header_name] = header_value
    end
    headers_hash
  end

end
