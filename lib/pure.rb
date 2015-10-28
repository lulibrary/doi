module Pure

  private

  def has_doi?(xml)
    doc = Nokogiri::XML(xml)
    ns = doc.collect_namespaces
    doc.xpath("//stab:dois/core:doi", ns).count > 0 ? true : false
  end

  def pure_dataset_exists?(xml)
    return pure_native_dataset_exists?(xml)
    # return pure_local_dataset_exists?(xml)
  end

  def pure_native_dataset_exists?(xml)
    doc = Nokogiri::XML(xml)
    # ns = doc.collect_namespaces
    ns = {"xmlns:core" =>
              "http://atira.dk/schemas/pure4/model/core/stable"}
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

  def pure_dataset_summary(pure_dataset_metadata)
    return pure_native_dataset_summary(pure_dataset_metadata)
    # return pure_local_dataset_summary(pure_dataset_metadata)
  end

  def pure_native_dataset_summary(pure_dataset_metadata)
    doc = Nokogiri::XML(pure_dataset_metadata)
    ns = doc.collect_namespaces
    summary = {}
    summary['title'] = doc.xpath("//stab:title/core:localizedString", ns).text
    creator_first_name = doc.xpath("//stab:persons/*[1]/person-template:name/core:firstName", ns).text
    creator_last_name = doc.xpath("//stab:persons/*[1]/person-template:name/core:lastName", ns).text
    summary['creator_name'] = creator_last_name + ', ' + creator_first_name
    summary['pure_uuid'] = doc.xpath("//core:content/@uuid", ns).text
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

end