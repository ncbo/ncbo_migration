require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'date'
require 'progressbar'
require 'open-uri'


only_migrate_ontologies = []
only_migrate_formats = []

errors = []
errors << "Could not find users, please run user migration: bundle exec ruby users.rb" if LinkedData::Models::User.all.empty?
errors << "Could not find categories, please run user migration: bundle exec ruby categories.rb" if LinkedData::Models::Category.all.empty?
errors << "Could not find groups, please run user migration: bundle exec ruby groups.rb" if LinkedData::Models::Group.all.empty?
abort("ERRORS:\n#{errors.join("\n")}") unless errors.empty?

# Prep Goo enums
LinkedData::Models::SubmissionStatus.init
LinkedData::Models::OntologyFormat.init

# Don't process the following formats
skip_formats = ["RRF", "UMLS-RELA", "PROTEGE", "LEXGRID-XML"]

# Transform old formats to new names
format_mapping = {
  "OBO" => "OBO",
  "OWL" => "OWL",
  "OWL-DL" => "OWL",
  "OWL-FULL" => "OWL",
  "OWL-LITE" => "OWL",
  "RRF" => "UMLS",
  "UMLS-RELA" => "UMLS",
  "PROTEGE" => "PROTEGE",
  "LEXGRID-XML" => "UMLS"
}

# Default download files value should be true
Kernel.const_defined?("DOWNLOAD_FILES") ? nil : DOWNLOAD_FILES = true

# Should we get all versions of every ontology, default to false
Kernel.const_defined?("ALL_ONTOLOGY_VERSIONS") ? nil : ALL_ONTOLOGY_VERSIONS = false

# Hard-coded master files for ontologies that have zips with multiple files
master_file = {"OCRe" => "OCRe.owl", "ICPS" => "PatientSafetyIncident.owl"}

acronyms = Set.new
names = Set.new
virtual_to_acronym = {}

# Track the bad data
duplicates = []
skipped = []
no_contacts = []
bad_urls = []
zip_multiple_files = []
missing_abbreviation = []
missing_users = []
bad_formats = []

latest = RestHelper.ontologies

# Remove all other ontologies if user specifies only migrating certain ones
if only_migrate_ontologies && !only_migrate_ontologies.empty?
  latest.delete_if {|o| !only_migrate_ontologies.include?(o.abbreviation)}
end

# Remove all ontologies that aren't in the requested format
if only_migrate_formats && !only_migrate_formats.empty?
  latest.delete_if {|o| !only_migrate_formats.include?(format_mapping[o.format])}
end

# Ontology-level checks
latest.each do |ont|
  if acronyms.include?(ont.abbreviation.downcase)
    duplicates << ont.abbreviation
    next
    # ont.abbreviation = ont.abbreviation + "-DUPLICATE-ACRONYM"
  elsif names.include?(ont.displayLabel.downcase)
    duplicates << ont.displayLabel
    ont.displayLabel = ont.displayLabel + " DUPLICATE NAME"
  end
  acronyms << ont.abbreviation.downcase
  names << ont.displayLabel.downcase
  virtual_to_acronym[ont.ontologyId] = ont.abbreviation
end

# Do not create ontologies with duplicate acronyms
latest.delete_if {|o| duplicates.include?(o.abbreviation)}

# Process latest and save ontology objects
puts "", "Number of ontologies to migrate: #{latest.length}"
pbar = ProgressBar.new("Migrating", latest.length)
latest.each do |ont|
  if ont.abbreviation.nil?
    missing_abbreviation << "#{ont.displayLabel}, #{ont.id}"
    next
  end
  
  o                    = LinkedData::Models::Ontology.new
  o.acronym            = ont.abbreviation
  o.name               = ont.displayLabel
  o.viewingRestriction = ont.viewingRestriction
  o.doNotUpdate        = ont.isManual == 1
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
  user_ids = ont.userIds[0][:int].kind_of?(Array) ? ont.userIds[0][:int] : [ ont.userIds[0][:int] ] rescue []
  user_ids.each do |user_id|
    begin
      old_user = RestHelper.user(user_id)
    rescue Exception => e
      missing_users << "#{ont.id}, #{user_id}"
      next
    end
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
end

# For submissions, either get all versions or use what we have
submissions = []
if ALL_ONTOLOGY_VERSIONS
  latest.each do |ont|
    versions = RestHelper.ontology_versions(ont.ontologyId)
    versions = versions.kind_of?(Array) ? versions : [versions]
    submissions = submissions + versions
  end
else
  submissions = latest
end

puts "", "Number of submissions to migrate: #{submissions.length}"
pbar = ProgressBar.new("Migrating", submissions.length*2)
submissions.each do |ont|
  begin
  acronym = virtual_to_acronym[ont.ontologyId]
  if acronym.nil?
    missing_abbreviation << "#{ont.displayLabel}, #{ont.id}"
    next
  end
  
  # Check to make sure Ontology is persistent, otherwise lookup again
  o = LinkedData::Models::Ontology.find(acronym)
  next if o.nil?
  
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
  os.summaryOnly        = ont.isMetadataOnly == 1
  os.pullLocation       = RestHelper.new_iri(ont.downloadLocation)
  os.submissionStatus   = LinkedData::Models::SubmissionStatus.find("UPLOADED")
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
  os.contact = contact

  # Ont format
  format = format_mapping[ont.format]
  if format.nil? || format.empty?
    bad_formats << "#{ont.abbreviation}, #{ont.id}, #{format}"
  else
    os.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find(format)
  end
  
  # UMLS ontologies get a special download location
  if format.eql?("UMLS")
    os.pullLocation = RestHelper.new_iri("#{UMLS_DOWNLOAD_SITE}/#{acronym.upcase}.ttl")
  end
  
  # Ontology file
  if skip_formats.include?(format) || !DOWNLOAD_FILES
    os.summaryOnly = true
    skipped << "#{ont.abbreviation}, #{ont.id}, #{ont.format}"
  elsif !os.summaryOnly.parsed_value
    begin
      # Get file
      if os.pullLocation
        if os.remote_file_exists?(os.pullLocation.value)
          # os.download_and_store_ontology_file
          file, filename = RestHelper.get_file(os.pullLocation.value)
          file_location = os.class.copy_file_repository(o.acronym, os.submissionId, file, filename)
          os.uploadFilePath = File.expand_path(file_location, __FILE__)
          if format.eql?("UMLS")
            semantic_types = open("#{UMLS_DOWNLOAD_SITE}/umls_semantictypes.ttl") rescue File.new
            File.open(os.uploadFilePath.to_s, 'a+') {|f| f.write(semantic_types.read) }
          end
        else
          bad_urls << "#{o.acronym}, #{ont.id}, #{os.pullLocation.value}"
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
            puts "Could not save ontology submission after setting master file, #{os.ontology.acronym}/#{os.submissionId}, #{os.errors}"
          end
        else
          zip_multiple_files << "#{o.acronym}, #{ont.id}, #{os.errors[:uploadFilePath].first[:options]}"
        end
      else
        puts "Could not save ontology submission, #{ont.abbreviation}, #{ont.id}, #{os.errors}"
      end
    end
  rescue Exception => e
    puts "Could not save ontology submission (error), #{ont.abbreviation}, #{ont.id}, #{os.errors || ""}, #{e.message}, \n  #{e.backtrace.join("\n  ")}"
  end
  
  pbar.inc
  rescue Exception => e
    binding.pry
  end
end
pbar.finish

puts ""
puts "Bad formats:"
puts bad_formats.empty? ? "None" : bad_formats.join("\n")

puts ""
puts "Missing abbreviation:"
puts missing_abbreviation.empty? ? "None" : missing_abbreviation.join("\n")

puts ""
puts "The following users submitted ontologies but no longer exist:"
puts missing_users.empty? ? "None" : missing_users.join("\n")

puts ""
puts "Duplicate ontology names/acronyms (ontologies skipped):"
puts duplicates.empty? ? "None" : duplicates.join("\n")

puts ""
puts "Entered as `summaryOnly` because we don't support this format yet:"
puts skipped.empty? || DOWNLOAD_FILES == false ? "None" : skipped.join("\n")

puts ""
puts "Missing contact information:"
puts no_contacts.empty? ? "None" : no_contacts.join("\n")

puts ""
puts "Bad file URLs:"
puts bad_urls.empty? ? "None" : bad_urls.join("\n")

puts ""
puts "Multiple files in zip:"
puts zip_multiple_files.empty? ? "None" : zip_multiple_files.join("\n")