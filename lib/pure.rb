module Pure

  private

  def in_output_whitelist?(output)
    whitelist = ['Dataset', 'Doctoral Thesis', "Master's Thesis"]
    whitelist.include? output
  end

  def determine_pure_resource_from_id(pure_id)
    data = {}
    # is it a dataset?
    dataset_extractor = Puree::Extractor::Dataset.new @pure_config
    metadata_model = dataset_extractor.find pure_id
    if metadata_model
      data['model'] = metadata_model
      data['type'] = 'Dataset'
      return data
    end

    # is it a research output of some kind?
    research_output_extractor = Puree::Extractor::ResearchOutput.new @pure_config
    metadata_model = research_output_extractor.find pure_id
    if metadata_model
      data['model'] = metadata_model
      data['type'] = 'ResearchOutput'
      return data
    end

    data
  end

  def resource_type_from_resource_type_id(resource_type_id)
    # 1 Dataset
    # 2 Thesis
    return 'Dataset' if resource_type_id === 1
    return 'Thesis' if resource_type_id === 2
    return nil
  end






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

  # Get a summary of a Pure record
  #
  # output_type is based on Pure's research output type
  # Dataset is not considered an output type in Pure but for consistency here it is included (uppercase)
  # Publication types are raw values from the Pure API (uppercase) via Puree e.g. 'Doctoral Thesis'
  def pure_native_summary(pure_metadata)
    summary = {}
    summary['model'] = pure_metadata.class.to_s.gsub('Puree::Model::','').downcase

    output_type = nil
    if summary['model'] === 'researchoutput'
      output_type = pure_metadata.type
    end
    if summary['model'] === 'dataset'
      output_type = 'Dataset'
    end
    summary['output_type'] = output_type
    # if output_type === 'Dataset'
    #   transformer = ResearchMetadata::Transformer::Dataset.new @pure_config
    # end
    # if output_type === 'Doctoral Thesis'
    #   transformer = ResearchMetadata::Transformer::Publication.new @pure_config
    # end
    # if output_type === "Master's Thesis"
    #   transformer = ResearchMetadata::Transformer::Publication.new @pure_config
    # end
    summary['title'] = pure_metadata.title
    creator_name = ''
    if !pure_metadata.persons_internal.empty?
      creator_name = pure_metadata.persons_internal[0].name.last_first
    elsif !pure_metadata.persons_external.empty?
      creator_name = pure_metadata.persons_external[0].name.last_first
    elsif !pure_metadata.persons_other.empty?
      creator_name = pure_metadata.persons_other[0].name.last_first
    end
    summary['creator_name'] = creator_name
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