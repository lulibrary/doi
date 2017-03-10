module Pure

  private

  def has_doi?(xml)
    doc = Nokogiri::XML(xml)
    ns = doc.collect_namespaces
    pure_dataset_response_type = get_pure_dataset_response_type(doc)
    doc.xpath("//" + pure_dataset_response_type + ":dois/core:doi", ns).count > 0 ? true : false
  end

  def pure_dataset_exists?(xml)
    return pure_native_dataset_exists?(xml)
    # return pure_local_dataset_exists?(xml)
  end

  def pure_native_dataset_exists?(xml)
    doc = Nokogiri::XML(xml)
    ns = doc.collect_namespaces
    # ns = {"xmlns:core" =>
    #           "http://atira.dk/schemas/pure4/model/core/stable"}
    # logger.info '**** XPATH RESULT ' + doc.xpath("//core:result/core:content", ns).length.to_s
    if doc.xpath("//core:result/core:content", ns).empty?
      return false
    end
    return true
  end

  def pure_local_dataset_exists?(xml)
    doc = Nokogiri::XML(xml)
    # ns = doc.collect_namespaces
    ns = {"xmlns:a" =>
              "http://schemas.datacontract.org/2004/07/Pure.WebServices.Domain"}
    if doc.xpath("//a:Dataset", ns).empty?
      return false
    end
    return true
  end

  def pure_summary(pure_metadata)
    return pure_native_summary(pure_metadata)
    # return pure_local_dataset_summary(pure_dataset_metadata)
  end

  # def pure_native_dataset_summary(pure_dataset_metadata)
  #   doc = Nokogiri::XML(pure_dataset_metadata)
  #   ns = doc.collect_namespaces
  #   pure_dataset_response_type = get_pure_dataset_response_type(doc)
  #   summary = {}
  #   summary['title'] = doc.xpath("//" + pure_dataset_response_type + ":title/core:localizedString", ns).text
  #   creator_first_name = doc.xpath("//" + pure_dataset_response_type + ":persons/*[1]/person-template:name/core:firstName", ns).text
  #   creator_last_name = doc.xpath("//" + pure_dataset_response_type + ":persons/*[1]/person-template:name/core:lastName", ns).text
  #   summary['creator_name'] = creator_last_name + ', ' + creator_first_name
  #   summary['pure_uuid'] = doc.xpath("//core:content/@uuid", ns).text
  #   summary
  # end

  def pure_native_summary(pure_metadata)
    summary = {}
    summary['title'] = pure_metadata.title
    summary['creator_name'] = pure_metadata.persons_internal[0].name.last_first
    summary['pure_uuid'] = pure_metadata.uuid
    summary
  end

  def pure_local_dataset_summary(pure_dataset_metadata)
    doc = Nokogiri::XML(pure_dataset_metadata)
    ns = doc.collect_namespaces
    summary = {}
    summary['title'] = doc.xpath("//a:Dataset/a:Title", ns).text
    summary['creator_name'] = doc.xpath("//a:Dataset/a:CreatorName", ns).text
    summary
  end

  def get_pure_dataset_response_type(doc)
    ns = doc.collect_namespaces
    # get cur or stab before the colon
    return doc.xpath("//core:result/core:content/@xsi:type", ns).text.split(":")[0]
  end

end