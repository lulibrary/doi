module CrosswalkPureToDatacite

  private

  def crosswalk_pure_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
    return crosswalk_pure_native_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
    # return crosswalk_pure_local_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
  end

  def crosswalk_pure_native_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
    doc = Nokogiri::XML(pure_dataset_metadata)
    ns = doc.collect_namespaces

    pure_dataset_response_type = get_pure_dataset_response_type(doc)

    builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
      xml.resource( 'xmlns' => 'http://datacite.org/schema/kernel-3',
                    'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                    'xsi:schemaLocation' => 'http://datacite.org/schema/kernel-3 http://schema.datacite.org/meta/kernel-3/metadata.xsd'
      ) {
        xml.identifier doi, :identifierType => 'DOI'
        xml.creators {
          creator_path = "//" + pure_dataset_response_type +
              ":dataSetPersonAssociation[person-template:personRole/core:term/core:localizedString='Creator']"
          doc.xpath(creator_path, ns).each do |creator|
            xml.creator {
              xml.creatorName creator.xpath("person-template:name/core:lastName", ns).text + ', ' + creator.xpath("person-template:name/core:firstName", ns).text
              uuid = creator.xpath("person-template:person/@uuid", ns).text
              if uuid
                orcid = pure_native_orcid(uuid)
                if orcid.length == 19
                  xml.nameIdentifier orcid, :schemeURI => 'http://orcid.org/', :nameIdentifierScheme => 'ORCID'
                end
              end
              creator.xpath("person-template:organisations//organisation-template:name/core:localizedString", ns).each do |affiliation|
                xml.affiliation affiliation.text
              end
            }
          end
        }

        # contributors (non creators)
        non_creator_path = "//" + pure_dataset_response_type +
            ":dataSetPersonAssociation[person-template:personRole/core:term/core:localizedString!='Creator']"
        non_creator_contributor_types = doc.xpath(non_creator_path, ns)
        if !non_creator_contributor_types.empty?
          # Pure to DataCite types map
          contributorTypes = {
              'Owner' => 'Other',
              'Contributor' => 'Other',
              'Data Collector' => 'DataCollector',
              'Data Manager' => 'DataManager',
              'Distributor' => 'Distributor',
              'Editor' => 'Editor',
              'Funder' => 'Funder',
              'Producer' => 'Producer',
              'Rights Holder' => 'RightsHolder',
              'Sponsor' => 'Sponsor',
              'Supervisor' => 'Supervisor',
              'Other' => 'Other'
          }
          xml.contributors {
            contributorTypes.each do |contributorTypePure, contributorTypeDataCite|
              contributor_path = "//" + pure_dataset_response_type + ":dataSetPersonAssociation[person-template:personRole/core:term/core:localizedString='"+contributorTypePure+"']"
              doc.xpath(contributor_path, ns).each do |contributor|
                xml.contributor(:contributorType => contributorTypeDataCite) {
                  xml.contributorName contributor.xpath("person-template:name/core:lastName", ns).text + ', ' + contributor.xpath("person-template:name/core:firstName", ns).text
                  uuid = contributor.xpath("person-template:person/@uuid", ns).text
                  if uuid
                    orcid = pure_native_orcid(uuid)
                    if orcid.length == 19
                      xml.nameIdentifier orcid, :schemeURI => 'http://orcid.org/', :nameIdentifierScheme => 'ORCID'
                    end
                  end
                  contributor.xpath("person-template:organisations//organisation-template:name/core:localizedString", ns).each do |affiliation|
                    xml.affiliation affiliation.text
                  end
                }
              end
            end
          }
        end

        xml.titles {
          xml.title doc.xpath("//" + pure_dataset_response_type + ":title/core:localizedString", ns).text
        }
        description_path = "//" + pure_dataset_response_type + ":descriptions//extensions-core:value/core:localizedString"
        if !doc.xpath(description_path, ns).empty?
          xml.descriptions {
            xml.description doc.xpath(description_path, ns).text, :descriptionType => 'Abstract'
            # Use cdata to cope with &
            #xml.description(:descriptionType => 'Abstract') {
            #  xml.cdata doc.xpath(description_path, ns).text
            #}
          }
        end

        xml.publisher doc.xpath("//" + pure_dataset_response_type + ":publisher//publisher-template:name", ns).text

        t = Time.parse(doc.xpath("//core:content/core:created", ns).text)
        xml.publicationYear t.strftime("%Y")

        keyword_group_path = "//core:content/core:keywordGroups/core:keywordGroup/core:keyword/core:userDefinedKeyword/core:freeKeyword"
        if !doc.xpath(keyword_group_path, ns).empty?
          xml.subjects {
            doc.xpath(keyword_group_path, ns).each do |keyword_group|
              words = keyword_group.text.split(',')
              words.each do |word|
                xml.subject word
              end
            end
          }
        end

        xml.resourceType 'Dataset', :resourceTypeGeneral => 'Dataset'
        xml.alternateIdentifiers {
          xml.alternateIdentifier doc.xpath("//core:content/@uuid", ns).text, :alternateIdentifierType => 'Pure UUID'
        }
        xml.dates {
          # available
          year = doc.xpath("//" + pure_dataset_response_type + ":dateMadeAvailable/core:year", ns).text
          month = doc.xpath("//" + pure_dataset_response_type + ":dateMadeAvailable/core:month", ns).text
          day = doc.xpath("//" + pure_dataset_response_type + ":dateMadeAvailable/core:day", ns).text
          ymd = ''
          if !year.empty?
            ymd << year
          end
          if !month.empty?
            # Add leading zero to convert to ISO 8601
            if month.length < 2
              month.insert(0, '0')
            end
            ymd << '-' + month
          end
          if !day.empty?
            # Add leading zero to convert to ISO 8601
            if day.length < 2
              day.insert(0, '0')
            end
            ymd << '-' + day
          end
          if ymd
            xml.date ymd, :dateType => 'Available'
          end

          dateRangeCollected = date_range_collected(doc)
          if !dateRangeCollected.empty?
            xml.date dateRangeCollected, :dateType => 'Collected'
          end
        }

        locale = doc.xpath("//" + pure_dataset_response_type + ":title/core:localizedString/@locale", ns).text
        locale = locale.gsub('_', '-').downcase
        xml.language locale

        geoLocationPlace = doc.xpath("//" + pure_dataset_response_type + ":geographicalCoverage/core:localizedString", ns).text
        # will need to test for numerical geolocations when implemented in order to create a <geoLocations> element
        if geoLocationPlace.length > 0
          xml.geoLocations {
            xml.geoLocation {
              xml.geoLocationPlace geoLocationPlace
            }
          }
        end

        # sizes
        sizes = doc.xpath("//" + pure_dataset_response_type + ":documents//core:size", ns)
        if !sizes.empty?
          xml.sizes {
            sizes.each do |size|
              xml.size size.text
            end
          }
        end

        # formats
        formats = doc.xpath("//" + pure_dataset_response_type + ":documents//core:mimeType", ns)
        if !formats.empty?
          xml.formats {
            formats.each do |format|
              xml.format format.text
            end
          }
        end

        # licenses (current xml response only)
        licenses = doc.xpath("//" + pure_dataset_response_type + ":documents//" + pure_dataset_response_type + ":documentLicense", ns)
        if !licenses.empty?
          xml.rightsList {
            licenses.each do |license|
              rights = license.xpath("core:term/core:localizedString", ns)
              rightsURI = license.xpath("core:description/core:localizedString", ns)
              xml.rights rights.text, :rightsURI => rightsURI.text
            end
          }
        end

        includeRelatedContent = true
        if includeRelatedContent === true
          # related content (current xml response only)
          relatedPublicationUUIDs = doc.xpath("//" + pure_dataset_response_type + ":relatedPublications/core:relatedContent/@uuid", ns)

          # AS AT 2016-01-14 THERE IS NO SEMANTICALLY MEANINGFUL WAY TO INCLUDE THE RELATED PROJECT(S) IN THE METADATA
          # isDocumentedBy for a project url (stab1:projectURL) is the closest but inaccurate as it describes the project not the dataset
          # relatedProjectUUIDs = doc.xpath("//" + pure_dataset_response_type + ":relatedProjects/core:relatedContent/@uuid", ns)

          relatedContent = false
          if !relatedPublicationUUIDs.empty?        # || !relatedProjectUUIDs.empty?
            relatedContent = true
          end

          if relatedContent === true
            xml.relatedIdentifiers {

              # related publications
              if !relatedPublicationUUIDs.empty?
                relatedPublicationUUIDs.each do |relatedPublicationUUID|
                  relatedPublicationXMLResponse = get_publication_from_uuid_pure_native(relatedPublicationUUID)
                  if relatedPublicationXMLResponse.code === '200'
                    relatedPublicationDoc = Nokogiri::XML(relatedPublicationXMLResponse.body)
                    relatedPublicationNs = relatedPublicationDoc.collect_namespaces
                    #logger.info 'relatedPublicationNs ' + relatedPublicationNs
                    if relatedPublicationNs['xmlns:publication-base_uk']
                      # dois
                      relatedPublicationDois = relatedPublicationDoc.xpath("//publication-base_uk:dois/core:doi/core:doi", relatedPublicationNs)
                      if !relatedPublicationDois.empty?
                        doi_prefix = 'http://dx.doi.org/'
                        relatedPublicationDois.each do |relatedPublicationDoi|
                          # Remove unwanted start of url
                          relatedPublicationDoiShortened = relatedPublicationDoi.text.sub(doi_prefix, '')
                          xml.relatedIdentifier relatedPublicationDoiShortened, :relatedIdentifierType => "DOI", :relationType => "IsSupplementTo"
                        end
                      end
                    end
                  end
                end
              end

              # related projects
              # AS AT 2016-01-14 THERE IS NO SEMANTICALLY MEANINGFUL WAY TO INCLUDE THE RELATED PROJECT(S) IN THE METADATA
              # isDocumentedBy for a project url (stab1:projectURL) is the closest but inaccurate as it describes the project not the dataset
              # if !relatedProjectUUIDs.empty?
              #
              # end
            }
          end
        end
      }
    end
    # logger.info builder.to_xml
    builder.to_xml

  end

  def date_range_collected(doc)
    ns = doc.collect_namespaces

    pure_dataset_response_type = get_pure_dataset_response_type(doc)

    startYear = doc.xpath("//" + pure_dataset_response_type + ":temporalCoverageStartDate/core:year", ns).text
    startMonth = doc.xpath("//" + pure_dataset_response_type + ":temporalCoverageStartDate/core:month", ns).text
    startDay = doc.xpath("//" + pure_dataset_response_type + ":temporalCoverageStartDate/core:day", ns).text
    startDate = ''
    if !startYear.empty?
      startDate << startYear
    end
    if !startMonth.empty?
      # Add leading zero to convert to ISO 8601
      if startMonth.length < 2
        startMonth.insert(0, '0')
      end
      startDate << '-' + startMonth
    end
    if !startDay.empty?
      # Add leading zero to convert to ISO 8601
      if startDay.length < 2
        startDay.insert(0, '0')
      end
      startDate << '-' + startDay
    end

    endYear = doc.xpath("//" + pure_dataset_response_type + ":temporalCoverageEndDate/core:year", ns).text
    endMonth = doc.xpath("//" + pure_dataset_response_type + ":temporalCoverageEndDate/core:month", ns).text
    endDay = doc.xpath("//" + pure_dataset_response_type + ":temporalCoverageEndDate/core:day", ns).text
    endDate = ''
    if !endYear.empty?
      endDate << endYear
    end
    if !endMonth.empty?
      # Add leading zero to convert to ISO 8601
      if endMonth.length < 2
        endMonth.insert(0, '0')
      end
      endDate << '-' + endMonth
    end
    if !endDay.empty?
      # Add leading zero to convert to ISO 8601
      if endDay.length < 2
        endDay.insert(0, '0')
      end
      endDate << '-' + endDay
    end

    if !startDate.empty? and !endDate.empty?
      return startDate + '/' + endDate
    else
      return ''
    end

  end

  def get_pure_dataset_response_type(doc)
    ns = doc.collect_namespaces
    # get cur or stab before the colon
    return doc.xpath("//core:result/core:content/@xsi:type", ns).text.split(":")[0]
  end

  def crosswalk_pure_local_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
    doc = Nokogiri::XML(pure_dataset_metadata)
    ns = doc.collect_namespaces

    builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
      xml.resource( 'xmlns' => 'http://datacite.org/schema/kernel-3',
                    'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                    'xsi:schemaLocation' => 'http://datacite.org/schema/kernel-3 http://schema.datacite.org/meta/kernel-3/metadata.xsd'
      ) {
        xml.identifier doi, :identifierType => 'DOI'
        xml.creators {
          doc.xpath("//a:Dataset/a:Creators/a:Creator[a:Role='Creator']", ns).each do |creator|
            xml.creator {
              xml.creatorName creator.at_xpath("a:LastName", ns).text + ', ' + creator.at_xpath("a:FirstName", ns).text
            }
          end
        }
        xml.titles {
          xml.title doc.xpath("//a:Dataset/a:Title", ns).text
        }
        xml.publisher doc.xpath("//a:Dataset/a:Publisher", ns).text
        xml.publicationYear doc.xpath("//a:Dataset/a:PublicationYear", ns).text
      }
    end
    builder.to_xml
  end
end