#!/usr/bin/env ruby

require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'logger'
require 'progressbar'

#FileUtils.mkdir_p("./logs")
#logger = Logger.new("logs/metrics_migrate.log")


if ENV['BP_ENV'] == 'STAGE'
  REST_URL ||= 'http://stagerest.bioontology.org/bioportal'
  UI_URL ||= 'http://stage.bioontology.org/ontologies'
else
  # Bypass the proxy?
  #REST_URL = 'http://ncboprod-core9.stanford.edu:8080/bioportal'
  REST_URL ||= 'http://rest.bioontology.org/bioportal'
  UI_URL ||= 'http://bioportal.bioontology.org/ontologies'
end

metricsCount = 0
ontologyCount = 0
ontologyCountValid = 0
warnings = []
failures = []

# Get all the ontology metadata in the old REST API production system
onts_old = RestHelper.ontologies
onts_old_by_acronym = {}
onts_old.each {|o| onts_old_by_acronym[o.abbreviation] = o}

# Get all the ontology metadata in the new REST API production system
onts_new = LinkedData::Models::Ontology.where.include(:acronym, :submissions => [:submissionId, :metrics]).all
onts_new_by_acronym = {}
onts_new.each {|o| onts_new_by_acronym[o.acronym] = o}

# Find all the common ontology acronyms (abbreviations)
acronymsOld = onts_old.map {|o| o.abbreviation }.to_set
acronymsNew = onts_new.map {|o| o.acronym }.to_set
acronymsAll = acronymsOld.intersection acronymsNew

# TODO: Issue warning about any old ontologies that are not in the new system?
#if ont_new.nil?
#  warningStr = "WARNING: skipping ontology, no match in new REST system: #{ontStr}."
#  warnings.push warningStr
#  puts warningStr if DEBUG
#  next
#end

acronymsAll.each do |acronym|

  ont_old = onts_old_by_acronym[acronym]
  ont_new = onts_new_by_acronym[acronym]

  # TODO: iterate through versions (submissions).
  #if ALL_ONTOLOGY_VERSIONS
  #  # Iterate over all the versions
  #end

  ontologyCount += 1
  ontStrData = [UI_URL, ont_old.ontologyId, ont_old.id, ont_old.internalVersionNumber, ont_old.abbreviation, ont_old.format]
  ontStr = sprintf("%s/%d (version: %5d, submission: %5d), %s (format: %s)", *ontStrData)
  #if not ont_old.format.start_with?('OWL')
  #    warningStr = "WARNING: skipping ontology, format != OWL: #{ontStr}."
  #    warnings.push warningStr
  #    puts warningStr if DEBUG
  #    next
  #end
  if ont_old.isMetadataOnly == 1
    # metadata only ontologies also have statusId = 5.
    warningStr = "WARNING: skipping ontology, metadata only: #{ontStr}."
    warnings.push warningStr
    puts warningStr if DEBUG
    next
  end
  if ont_old.statusId != 3
    warningStr = "WARNING: skipping ontology, statusId != 3 (#{ont_old.statusId}): #{ontStr}."
    warnings.push warningStr
    puts warningStr if DEBUG
    next
  end
  # Determine whether new REST API contains an ontology submission matching ont_old.internalVersionNumber
  ont_new_submissionIds = ont_new.submissions.map {|s| s.submissionId }
  if not ont_new_submissionIds.include? ont_old.internalVersionNumber
    warningStr = "WARNING: skipping ontology, no submission match in new REST system: #{ontStr}."
    warnings.push warningStr
    puts warningStr if DEBUG
    next
  end
  # Get the matching submission and determine whether it already has metrics available
  subIndex = ont_new_submissionIds.index(ont_old.internalVersionNumber)
  sub = ont_new.submissions[subIndex]
  if not sub.metrics.nil?
    warningStr = "WARNING: skipping ontology, submission already has metrics in new REST system: #{ontStr}."
    warnings.push warningStr
    puts warningStr if DEBUG
    next
  end
  #sub.bring_remaining


  # TODO: Get the old ontology metrics.

  # TODO: Assign the values into the new ontology metrics and save.


  binding.pry
  exit!






  exit!

  ontologyCountValid += 1
  $stdout.write "INFO: #{ontStr} ..."
  status = runMetrics(ont_old)  # returns 0 on failure, 1 on success
  if status == 0
    failures.push "FAILURE: #{ontStr}."
    #$stdout.write " OOPS: trying again, ontology #{ontStr} ..."
    #status = runMetrics(ont_old)  # returns 0 on failure, 1 on success
  end
  metricsCount += status

end




puts
puts warnings if not DEBUG
puts failures
puts "\n\nINFO: total ontology count: #{ontologyCount}."
puts "INFO: #{ontologyCountValid} candidate ontologies."
puts "INFO: updated metrics for #{metricsCount} ontologies."
puts
