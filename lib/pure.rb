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

  # Get a summary of a Pure record
  #
  # output_type is based on Pure's research output type
  # Dataset is not considered an output type in Pure but for consistency here it is included (uppercase)
  # Publication types are raw values from the Pure API (uppercase) via Puree e.g. 'Doctoral Thesis'
  def pure_summary(pure_metadata)
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
    summary['title'] = pure_metadata.title
    all_creators = creators(pure_metadata)
    if all_creators.empty?
      summary['creator_name'] = nil
    else
      summary['creator_name'] = all_creators.first.name.last_first
    end
    summary['pure_uuid'] = pure_metadata.uuid
    summary
  end

  # For UI verification, as sometimes Pure records are made without a creator
  # At least one creator is required by DataCite
  def creators(pure_metadata)
    creators = []
    pure_metadata.persons_internal.each do |i|
      creators << i if creator? i.role
    end
    pure_metadata.persons_external.each do |i|
      creators << i if creator? i.role
    end
    pure_metadata.persons_other.each do |i|
      creators << i if creator? i.role
    end
    creators
  end

  def creator?(role)
    roles = %w(creator author)
    roles.include? role.downcase
  end

end