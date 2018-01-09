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
    metadata_model = dataset_extractor.find id: pure_id
    if metadata_model
      data['model'] = metadata_model
      data['type'] = 'Dataset'
      return data
    end

    # is it a publication of some kind?
    publication_extractor = Puree::Extractor::Publication.new @pure_config
    metadata_model = publication_extractor.find id: pure_id
    if metadata_model
      data['model'] = metadata_model
      data['type'] = 'Publication'
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

  def pure_summary(pure_metadata)
    return pure_native_summary(pure_metadata)
  end

  # Get a summary of a Pure record
  #
  # output_type is based on Pure's research output type
  # Dataset is not considered an output type in Pure but for consistency here it is included (uppercase)
  # Publication types are raw values from the Pure API (uppercase) via Puree e.g. 'Doctoral Thesis'
  def pure_native_summary(pure_metadata)
    summary = {}
    summary['model'] = pure_metadata.class.to_s.gsub('Puree::Model::','').downcase

    output_type = nil
    if summary['model'] === 'publication'
      output_type = pure_metadata.type
    end
    if summary['model'] === 'dataset'
      output_type = 'Dataset'
    end
    summary['output_type'] = output_type
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

end