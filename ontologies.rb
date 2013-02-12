require 'date'
require 'progressbar'
require 'ontologies_linked_data'

require_relative 'helpers/rest_helper'

errors = []
errors << "Could not find users, please run user migration: bundle exec ruby users.rb" if LinkedData::Models::User.all.empty?
errors << "Could not find categories, please run user migration: bundle exec ruby categories.rb" if LinkedData::Models::Category.all.empty?
errors << "Could not find groups, please run user migration: bundle exec ruby groups.rb" if LinkedData::Models::Group.all.empty?
abort("ERRORS:\n#{errors.join("\n")}") unless errors.empty?

# Prep Goo enums
LinkedData::Models::SubmissionStatus.init
LinkedData::Models::OntologyFormat.init

# Don't process formats
skip_formats = ["RRF", "UMLS-RELA", "PROTEGE", "UMLS"]
format_mapping = {
  "OBO" => "OBO",
  "OWL" => "OWL",
  "OWL-DL" => "OWL",
  "OWL-FULL" => "OWL",
  "OWL-LITE" => "OWL",
  "RRF" => "UMLS",
  "UMLS-RELA" => "UMLS",
  "PROTEGE" => "PROTEGE"
}
master_file = {"OCRe" => "OCRe.owl", "ICPS" => "PatientSafetyIncident.owl"}

acronyms = Set.new
names = Set.new
duplicates = []
skipped = []
no_contacts = []
bad_urls = []
zip_multiple_files = []
puts "Number of ontologies to migrate: #{RestHelper.ontologies.length}"
pbar = ProgressBar.new("Migrating", RestHelper.ontologies.length*2)
RestHelper.ontologies.each_with_index do |ont, index|
  if acronyms.include?(ont.abbreviation.downcase)
    duplicates << ont.abbreviation
    ont.abbreviation = ont.abbreviation + "-DUPLICATE-ACRONYM"
  elsif names.include?(ont.displayLabel.downcase)
    duplicates << ont.displayLabel
    ont.displayLabel = ont.displayLabel + " DUPLICATE NAME"
  end
  acronyms << ont.abbreviation.downcase
  names << ont.displayLabel.downcase
  
  o                    = LinkedData::Models::Ontology.new
  o.acronym            = ont.abbreviation
  o.name               = ont.displayLabel
  o.viewingRestriction = ont.viewingRestriction
  o.doNotUpdate        = ont.isManuel == 1
  o.flat               = ont.isFlat == 1

  # ACL
  o.acl = []
  if !ont.userAcl.nil? && !ont.userAcl[0].eql?("")
    users = ont.userAcl[0][:userEntry].kind_of?(Array) ? ont.userAcl[0][:userEntry] : [ ont.userAcl[0][:userEntry] ]
    users.each do |user|
      old_user = RestHelper.user(user[:userId])
      new_user = LinkedData::Models::User.find(old_user.username)
      o.acl << new_user
    end
  end
  
  # Admins
  user_ids = ont.userIds[0][:int].kind_of?(Array) ? ont.userIds[0][:int] : [ ont.userIds[0][:int] ] rescue binding.pry
  user_ids.each do |user_id|
    old_user = RestHelper.user(user_id)
    new_user = LinkedData::Models::User.find(old_user.username)
    if o.administeredBy.nil?
      o.administeredBy = [new_user]
    else
      o.administeredBy << new_user
    end
  end
  
  # Groups
  o.group = []
  if !ont.groupIds.nil? && !ont.groupIds[0].eql?("")
    if ont.groupIds[0][:int].kind_of?(Array)
      ont.groupIds[0][:int].each do |group_id|
        group_acronym = RestHelper.safe_acronym(RestHelper.group(group_id).acronym)
        o.group << LinkedData::Models::Group.find(group_acronym)
      end
    else
      group_acronym = RestHelper.safe_acronym(RestHelper.group(ont.groupIds[0][:int]).acronym)
      o.group = LinkedData::Models::Group.find(group_acronym)
    end
  end
  
  # Categories
  o.hasDomain = []
  if !ont.categoryIds.nil? && !ont.categoryIds[0].eql?("")
    if ont.categoryIds[0][:int].kind_of?(Array)
      ont.categoryIds[0][:int].each do |cat_id|
        category_acronym = RestHelper.safe_acronym(RestHelper.category(cat_id).name)
        category = LinkedData::Models::Category.find(category_acronym)
        o.hasDomain << category
      end
    else
      category_acronym = RestHelper.safe_acronym(RestHelper.category(ont.categoryIds[0][:int]).name)
      category = LinkedData::Models::Category.find(category_acronym)
      o.hasDomain << category
    end
  end
  
  if o.valid?
    o.save
  elsif !o.exist?
    puts "Couldn't save #{o.acronym}, #{o.errors}"
  end
  
  pbar.inc
  
  # Check to make sure Ontology is persistent, otherwise lookup again
  o = o.persistent? ? o : LinkedData::Models::Ontology.find(o.acronym)
  
  # Submission
  os                    = LinkedData::Models::OntologySubmission.new
  os.submissionId       = ont.internalVersionNumber
  os.prefLabelProperty  = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.preferredNameSlot))
  os.definitionProperty = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.documentationSlot))
  os.synonymProperty    = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.synonymSlot))
  os.authorProperty     = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.authorSlot))
  os.obsoleteProperty   = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.obsoleteProperty))
  os.obsoleteParent     = RestHelper.new_iri(RestHelper.lookup_property_uri(ont.id, ont.obsoleteParent))
  os.homepage           = ont.homepage
  os.publication        = ont.publication.eql?("") ? nil : ont.publication
  os.documentation      = ont.documentation.eql?("") ? nil : ont.documentation
  os.version            = ont.versionNumber
  os.uri                = ont.urn
  os.naturalLanguage    = ont.naturalLanguage
  os.creationDate       = DateTime.parse(ont.dateCreated)
  os.released           = DateTime.parse(ont.dateReleased)
  os.description        = ont.description
  os.status             = ont.versionStatus
  os.summaryOnly        = ont.isMetadataOnly == 1
  os.pullLocation       = RestHelper.new_iri(ont.downloadLocation)
  os.submissionStatus   = LinkedData::Models::SubmissionStatus.find("UPLOADED")
  os.ontology           = o

  # Contact
  contact = LinkedData::Models::Contact.where(name: ont.contactName, email: ont.contactEmail)
  if contact.empty?
    name = ont.contactName || "UNKNOWN"
    email = ont.contactEmail || "UNKNOWN"
    no_contacts << "#{ont.abbreviation}, #{ont.contactName}, #{ont.contactEmail}" if [name, email].include?("UNKNOWN")
    contact = LinkedData::Models::Contact.new(name: name, email: email)
    contact.save
  else
    contact = contact.first
  end
  os.contact = contact

  # Ont format
  format = format_mapping[ont.format]
  os.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find(format)
  
  # Ontology file
  if skip_formats.include?(ont.format)
    os.summaryOnly = true
    skipped << "#{ont.abbreviation}, #{ont.format}"
  elsif !os.summaryOnly
    begin
      # Get file
      if os.pullLocation
        if os.remote_file_exists?(os.pullLocation.value)
          # os.download_and_store_ontology_file
          file, filename = RestHelper.get_file(os.pullLocation.value)
          file_location = os.class.copy_file_repository(o.acronym, os.submissionId, file, filename)
          os.uploadFilePath = file_location
        else
          bad_urls << "#{o.acronym}, #{os.pullLocation.value}"
          os.pullLocation = nil
          os.summaryOnly = true
        end
      else
        file, filename = RestHelper.ontology_file(ont.id)
        file_location = os.class.copy_file_repository(o.acronym, os.submissionId, file, filename)
        os.uploadFilePath = file_location
      end
    rescue Exception => e
      bad_urls << "#{o.acronym}, #{os.pullLocation || ""}, #{e.message}"
    end
  end
  
  if os.valid?
    os.save
  else
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
          puts "Could not save ontology submission after setting master file, #{os.ontology.acronym}/#{os.submissionId}, #{os.errors}"
        end
      else
        zip_multiple_files << "#{o.acronym}, #{os.errors[:uploadFilePath].first[:options]}"
      end
    else
      puts "Could not save ontology submission, #{os.ontology.acronym}/#{os.submissionId}, #{os.errors}"
    end
  end
  
  pbar.inc
end
pbar.finish

puts "Duplicate ontology names/acronyms (ontologies created with `DUPLICATE` appended):"
puts duplicates.empty? ? "None" : duplicates.join("\n")

puts ""
puts "Entered as `summaryOnly` because we don't support this format yet:"
puts skipped.empty? ? "None" : skipped.join("\n")

puts ""
puts "Missing contact information:"
puts no_contacts.empty? ? "None" : no_contacts.join("\n")

puts ""
puts "Bad file URLs:"
puts bad_urls.empty? ? "None" : bad_urls.join("\n")

puts ""
puts "Multiple files in zip:"
puts zip_multiple_files.empty? ? "None" : zip_multiple_files.join("\n")