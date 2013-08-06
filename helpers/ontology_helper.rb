def migrate_submission(ont, pbar, virtual_to_acronym, format_mapping, skip_formats, missing_abbreviation, bad_formats, skipped, bad_urls, no_contacts, master_file, zip_multiple_files)
  begin
    acronym = virtual_to_acronym[ont.ontologyId]
    if acronym.nil?
      missing_abbreviation << "#{ont.displayLabel}, #{ont.id}"
      return
    end

    # Check to make sure Ontology is persistent, otherwise lookup again
    o = LinkedData::Models::Ontology.find(acronym).include(LinkedData::Models::Ontology.attributes(:all)).first
    return if o.nil?

    # Submission
    os                    = LinkedData::Models::OntologySubmission.new
    os.submissionId       = ont.internalVersionNumber
    ##
    #
    #
    # TODO: Log bad property URIs
    #
    #
    ##
    os.prefLabelProperty  = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.preferredNameSlot))
    os.definitionProperty = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.documentationSlot))
    os.synonymProperty    = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.synonymSlot))
    os.authorProperty     = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.authorSlot))
    os.obsoleteProperty   = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.obsoleteProperty))
    os.obsoleteParent     = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.obsoleteParent))
    os.homepage           = ont.homepage
    os.publication        = ont.publication.eql?("") ? nil : ont.publication
    os.documentation      = ont.documentation.eql?("") ? nil : ont.documentation
    os.version            = ont.versionNumber.to_s
    os.uri                = ont.urn
    os.naturalLanguage    = ont.naturalLanguage
    os.creationDate       = DateTime.parse(ont.dateCreated)
    os.released           = DateTime.parse(ont.dateReleased)
    os.description        = ont.description
    os.status             = ont.versionStatus
    os.pullLocation       = RestHelper.new_iri(ont.downloadLocation)
    os.submissionStatus   = LinkedData::Models::SubmissionStatus.find("UPLOADED").first
    os.ontology           = o

    pbar.inc

    # Contact
    contact_name = ont.contactName || ont.contactEmail
    contact = LinkedData::Models::Contact.where(name: contact_name, email: ont.contactEmail) unless ont.contactEmail.nil?
    if contact.nil? || contact.empty?
      name = ont.contactName || "UNKNOWN"
      email = ont.contactEmail || "UNKNOWN"
      no_contacts << "#{ont.abbreviation}, #{ont.id}, #{ont.contactName}, #{ont.contactEmail}" if [name, email].include?("UNKNOWN")
      contact = LinkedData::Models::Contact.new(name: name, email: email)
      contact.save
    else
      contact = contact.first
    end
    os.contact = [contact]

    # Ont format
    format = format_mapping[ont.format]
    if format.nil? || format.empty?
      bad_formats << "#{ont.abbreviation}, #{ont.id}, #{format}"
    else
      os.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find(format).first
    end

    # UMLS ontologies get a special download location
    if format.eql?("UMLS")
      os.pullLocation = RestHelper.new_iri("#{UMLS_DOWNLOAD_SITE}/#{acronym.upcase}.ttl")
    end

    # Ontology file
    if skip_formats.include?(format) || !DOWNLOAD_FILES
      o.summaryOnly = true
      o.save
      skipped << "#{ont.abbreviation}, #{ont.id}, #{ont.format}"
    elsif !os.summaryOnly
      begin
        # Get file
        if os.pullLocation
          if os.remote_file_exists?(os.pullLocation.to_s)
            # os.download_and_store_ontology_file
            file, filename = RestHelper.get_file(os.pullLocation.to_s)
            file_location = os.class.copy_file_repository(o.acronym, os.submissionId, file, filename)
            os.uploadFilePath = File.expand_path(file_location, __FILE__)
            if format.eql?("UMLS")
              semantic_types = open("#{UMLS_DOWNLOAD_SITE}/umls_semantictypes.ttl") rescue File.new
              File.open(os.uploadFilePath.to_s, 'a+') {|f| f.write(semantic_types.read) }
            end
          else
            bad_urls << "#{o.acronym}, #{ont.id}, #{os.pullLocation.to_s}"
            os.pullLocation = nil
            os.summaryOnly = true
          end
        else
          file, filename = RestHelper.ontology_file(ont.id)
          file_location = os.class.copy_file_repository(o.acronym, os.submissionId, file, filename)
          os.uploadFilePath = File.expand_path(file_location, __FILE__)
        end
      rescue Exception => e
        bad_urls << "#{o.acronym}, #{ont.id}, #{os.pullLocation || ""}, #{e.message}"
      end
    end

    begin
      if os.valid?
        os.save
      elsif !os.exist?
        if (
        os.errors[:uploadFilePath] and
            os.errors[:uploadFilePath].kind_of?(Array) and
            os.errors[:uploadFilePath].first.kind_of?(Hash) and
            os.errors[:uploadFilePath].first[:message] and
            os.errors[:uploadFilePath].first[:message].start_with?("Zip file detected")
        )
          # Problem with multiple files
          if master_file.key?(o.acronym)
            os.masterFileName = master_file[o.acronym]
            if os.valid?
              os.save
            else
              puts "Could not save ontology/view submission after setting master file, #{os.ontology.acronym}/#{os.submissionId}, #{os.errors}"
            end
          else
            zip_multiple_files << "#{o.acronym}, #{ont.id}, #{os.errors[:uploadFilePath].first[:options]}"
          end
        else
          puts "Could not save ontology/view submission, #{ont.abbreviation}, #{ont.id}, #{os.errors}"
        end
      end
    rescue Exception => e
      puts "Could not save ontology/view submission (error), #{ont.abbreviation}, #{ont.id}, #{os.errors || ""}, #{e.message}, \n  #{e.backtrace.join("\n  ")}"
    end

    pbar.inc
  rescue Exception => e
    binding.pry
  end
end