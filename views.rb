require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'date'
require 'progressbar'
require 'open-uri'

require_relative 'helpers/ontology_helper'

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

acronyms = Set.new
names = Set.new
virtual_to_acronym = {}

# Track the bad data
missing_abbreviation = []
bad_formats = []
duplicates = []
skipped = []
bad_urls = []
no_contacts = []
master_file = {}
zip_multiple_files = []

# get all views across the old system
bp_latest_views = RestHelper.views

bp_latest_views.each do |view|
  if acronyms.include?(view.abbreviation.downcase)
    duplicates << view.abbreviation
    view.abbreviation = view.abbreviation + "-VIEW"
  elsif names.include?(view.displayLabel.downcase)
    duplicates << view.displayLabel
    view.displayLabel = view.displayLabel + " DUPLICATE NAME"
  end
  acronyms << view.abbreviation.downcase
  names << view.displayLabel.downcase
  virtual_to_acronym[view.ontologyId] = view.abbreviation
end

onts = LinkedData::Models::Ontology.all(load_attrs: [:acronym => true, :viewOf => true])
onts_by_acronym = {}

onts.each do |ont|
  if ont.viewOf.nil?
    onts_by_acronym[ont.acronym.value] = ont
  else
    onts.delete(ont)
  end
end

bp_latest_onts = RestHelper.ontologies
bp_latest_onts.select! { |bp_latest_ont| onts_by_acronym.include?(bp_latest_ont.abbreviation) }

bp_latest_onts.each do |bp_latest_ont|
  bp_ont_views = RestHelper.ontology_views(bp_latest_ont.ontologyId)

  pbar = ProgressBar.new("Number of views to migrate for ontology #{bp_latest_ont.abbreviation}: #{bp_ont_views.length}", bp_ont_views.length)
  view_ontology_ids = []

  bp_ont_views.each do |ont_view|
    if ont_view.abbreviation.nil?
      missing_abbreviation << "#{ont_view.displayLabel}, #{ont_view.id}"
      next
    end

    if !view_ontology_ids.include?(ont_view.ontologyId)
      v = LinkedData::Models::Ontology.new
      v.viewOf = onts_by_acronym[bp_latest_ont.abbreviation]

      o = LinkedData::Models::Ontology.find(ont_view.abbreviation)

      if (o.nil?)
        v.acronym = ont_view.abbreviation
      else
        v.acronym = "#{ont_view.abbreviation}-VIEW"
        virtual_to_acronym[ont_view.ontologyId] = v.acronym.value
      end

      v.name = ont_view.displayLabel
      v.doNotUpdate = ont_view.isManual == 1
      v.flat = ont_view.isFlat == 1

      # Admins
      user_ids = bp_latest_ont.userIds[0][:int].kind_of?(Array) ? bp_latest_ont.userIds[0][:int] : [ bp_latest_ont.userIds[0][:int] ] rescue []
      user_ids.each do |user_id|
        begin
          old_user = RestHelper.user(user_id)
        rescue Exception => e
          missing_users << "#{bp_latest_ont.id}, #{user_id}"
          next
        end
        new_user = LinkedData::Models::User.find(old_user.username)
        if v.administeredBy.nil?
          v.administeredBy = [new_user]
        else
          v.administeredBy << new_user
        end
      end

      if v.valid?
        v.save
      elsif !v.exist?
        puts "Couldn't save #{v.acronym}, #{v.errors}"
      end

      view_ontology_ids.push(ont_view.ontologyId)
      pbar.inc
    end

    migrate_submission(ont_view, pbar, virtual_to_acronym, format_mapping, skip_formats, missing_abbreviation, bad_formats, skipped, bad_urls, no_contacts, master_file, zip_multiple_files)
  end

  pbar.finish
end

puts ""
puts "Bad formats:"
puts bad_formats.empty? ? "None" : bad_formats.join("\n")

puts ""
puts "Missing abbreviation:"
puts missing_abbreviation.empty? ? "None" : missing_abbreviation.join("\n")

puts ""
puts "Duplicate view names/acronyms:"
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
