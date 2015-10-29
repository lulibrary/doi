module CrosswalkPureToDatacite

  private

  def crosswalk_pure_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
    return crosswalk_pure_native_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
    # return crosswalk_pure_local_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
  end

  def crosswalk_pure_native_to_datacite_dataset_metadata(doi, pure_dataset_metadata)
    doc = Nokogiri::XML(pure_dataset_metadata)
    ns = doc.collect_namespaces

    builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
      xml.resource( 'xmlns' => 'http://datacite.org/schema/kernel-3',
                    'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                    'xsi:schemaLocation' => 'http://datacite.org/schema/kernel-3 http://schema.datacite.org/meta/kernel-3/metadata.xsd'
      ) {
        xml.identifier doi, :identifierType => 'DOI'
        xml.creators {
          creator_path = "//stab:dataSetPersonAssociation[person-template:personRole/core:term/core:localizedString='Creator']"
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
        non_creator_path = "//stab:dataSetPersonAssociation[person-template:personRole/core:term/core:localizedString!='Creator']"
        non_creator_contributor_types = doc.xpath(non_creator_path, ns)
        if non_creator_contributor_types.count > 0
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
              contributor_path = "//stab:dataSetPersonAssociation[person-template:personRole/core:term/core:localizedString='"+contributorTypePure+"']"
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
          xml.title doc.xpath("//stab:title/core:localizedString", ns).text
        }
        description_path = "//stab:descriptions//extensions-core:value/core:localizedString"
        if doc.xpath(description_path, ns).count > 0
          xml.descriptions {
            # xml.create_cdata description, doc.xpath(description_path, ns).text, :descriptionType => 'Abstract'
            # Use cdata to cope with &
            xml.description(:descriptionType => 'Abstract') {
              xml.cdata doc.xpath(description_path, ns).text
            }
          }
        end

        xml.publisher doc.xpath("//stab:publisher//publisher-template:name", ns).text

        t = Time.parse(doc.xpath("//core:content/core:created", ns).text)
        xml.publicationYear t.strftime("%Y")

        keyword_group_path = "//core:content/core:keywordGroups/core:keywordGroup/core:keyword/core:userDefinedKeyword/core:freeKeyword"
        if doc.xpath(keyword_group_path, ns).count > 0
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
          year = doc.xpath("//stab:dateMadeAvailable/core:year", ns).text
          month = doc.xpath("//stab:dateMadeAvailable/core:month", ns).text
          day = doc.xpath("//stab:dateMadeAvailable/core:day", ns).text
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

        locale = doc.xpath("//stab:title/core:localizedString/@locale", ns).text
        locale = locale.gsub('_', '-').downcase
        xml.language locale

        geoLocationPlace = doc.xpath("//stab:geographicalCoverage/core:localizedString", ns).text
        # will need to test for numerical geolocations when implemented in order to create a <geoLocations> element
        if geoLocationPlace.length > 0
          xml.geoLocations {
            xml.geoLocation {
              xml.geoLocationPlace geoLocationPlace
            }
          }
        end

        # sizes
        sizes = doc.xpath("//stab:documents//core:size", ns)
        if sizes.count > 0
          xml.sizes {
            sizes.each do |size|
              xml.size size.text
            end
          }
        end

        # formats
        formats = doc.xpath("//stab:documents//core:mimeType", ns)
        if formats.count > 0
          xml.formats {
            formats.each do |format|
              xml.format format.text
            end
          }
        end
      }
    end
    # logger.info builder.to_xml
    builder.to_xml

  end

  def date_range_collected(doc)
    ns = doc.collect_namespaces

    startYear = doc.xpath("//stab:temporalCoverageStartDate/core:year", ns).text
    startMonth = doc.xpath("//stab:temporalCoverageStartDate/core:month", ns).text
    startDay = doc.xpath("//stab:temporalCoverageStartDate/core:day", ns).text
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

    endYear = doc.xpath("//stab:temporalCoverageEndDate/core:year", ns).text
    endMonth = doc.xpath("//stab:temporalCoverageEndDate/core:month", ns).text
    endDay = doc.xpath("//stab:temporalCoverageEndDate/core:day", ns).text
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