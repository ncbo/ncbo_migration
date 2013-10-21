require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'date'
require 'logger'
require 'progressbar'
require 'open-uri'

require_relative 'helpers/ontology_helper'

FileUtils.mkdir_p("./logs")
logger = Logger.new("logs/ontologies_migration.log")

only_migrate_ontologies = []
only_migrate_formats = []
override_administeredBy_usernames = []
migrate_views = true
associate_groups = true
associate_categories = true

errors = []
errors << "Could not find users, please run user migration: bundle exec ruby users.rb" if LinkedData::Models::User.all.empty?
errors << "Could not find categories, please run user migration: bundle exec ruby categories.rb" if LinkedData::Models::Category.all.empty?
errors << "Could not find groups, please run user migration: bundle exec ruby groups.rb" if LinkedData::Models::Group.all.empty?
abort("ERRORS:\n#{errors.join("\n")}") unless errors.empty?

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
master_file = {
  "OCRE" => "OCRe.owl",
  "ICPS" => "PatientSafetyIncident.owl",
  "CTX" => "XCTontologyvtemp2/XCTontologyvtemp2.owl",
  "CBO" => "cbo.owl",
  "ICNP" => "ICNP_2013_OWL_public_use.owl"
}

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
latest.dup.each do |ont|
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
  o.summaryOnly        = ont.isMetadataOnly == 1

  # ACL
  o.acl = []
  if !ont.userAcl.nil? && !ont.userAcl[0].eql?("")
    users = ont.userAcl[0][:userEntry].kind_of?(Array) ? ont.userAcl[0][:userEntry] : [ ont.userAcl[0][:userEntry] ]
    users.dup.each do |user|
      old_user = RestHelper.user(user[:userId])
      new_user = LinkedData::Models::User.find(old_user.username).include(LinkedData::Models::User.attributes(:all)).first
      o.acl = [new_user] + o.acl
    end
  end

  # Admins
  if override_administeredBy_usernames && !override_administeredBy_usernames.empty?
    # Get users from the provided list
    users = override_administeredBy_usernames.map {|u| LinkedData::Models::User.find(u).include(LinkedData::Models::User.attributes(:all)).first}
    o.administeredBy = users
  else
    # Use existing admins
    user_ids = ont.userIds[0][:int].kind_of?(Array) ? ont.userIds[0][:int] : [ ont.userIds[0][:int] ] rescue []
    user_ids.each do |user_id|
      begin
        old_user = RestHelper.user(user_id)
      rescue Exception => e
        missing_users << "#{ont.id}, #{user_id}"
        next
      end
      new_user = LinkedData::Models::User.find(old_user.username).include(LinkedData::Models::User.attributes(:all)).first
      if o.administeredBy.nil?
        o.administeredBy = [new_user]
      else
        o.administeredBy = [new_user] + o.administeredBy
      end
    end
  end

  # Groups
  if associate_groups
    o.group = []
    if !ont.groupIds.nil? && !ont.groupIds[0].eql?("")
      if ont.groupIds[0][:int].kind_of?(Array)
        ont.groupIds[0][:int].each do |group_id|
          group_acronym = RestHelper.safe_acronym(RestHelper.group(group_id).acronym)
          o.group = [LinkedData::Models::Group.find(group_acronym).include(LinkedData::Models::Group.attributes(:all)).first] + o.group
        end
      else
        group_acronym = RestHelper.safe_acronym(RestHelper.group(ont.groupIds[0][:int]).acronym)
        o.group = [LinkedData::Models::Group.find(group_acronym).include(LinkedData::Models::Group.attributes(:all)).first]
      end
    end
  end

  # Categories
  if associate_categories
    o.hasDomain = []
    if !ont.categoryIds.nil? && !ont.categoryIds[0].eql?("")
      if ont.categoryIds[0][:int].kind_of?(Array)
        ont.categoryIds[0][:int].each do |cat_id|
          category_acronym = RestHelper.safe_acronym(RestHelper.category(cat_id).name)
          category = LinkedData::Models::Category.find(category_acronym).include(LinkedData::Models::Category.attributes(:all)).first
          o.hasDomain = [category] + o.hasDomain
        end
      else
        category_acronym = RestHelper.safe_acronym(RestHelper.category(ont.categoryIds[0][:int]).name)
        category = LinkedData::Models::Category.find(category_acronym).include(LinkedData::Models::Category.attributes(:all)).first
        o.hasDomain = [category] + o.hasDomain
      end
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
    submissions += versions.kind_of?(Array) ? versions : [versions]
  end
else
  submissions = latest
end

puts "", "Number of submissions to migrate: #{submissions.length}"
pbar = ProgressBar.new("Migrating", submissions.length*2)
submissions.each do |ont|
  migrate_submission(logger, ont, pbar, virtual_to_acronym, format_mapping, skip_formats, missing_abbreviation, bad_formats, skipped, bad_urls, no_contacts, master_file, zip_multiple_files)
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

require_relative "semantic_types"
