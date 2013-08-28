#!/usr/bin/env ruby

require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'logger'
require 'progressbar'

# TODO: Use logger.
#FileUtils.mkdir_p("./logs")
#logger = Logger.new("logs/metrics_migrate.log")

DEBUG = true

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
acronyms_old = onts_old.map {|o| o.abbreviation }.to_set
acronyms_new = onts_new.map {|o| o.acronym }.to_set
acronyms_common = acronyms_old.intersection acronyms_new

# TODO: Issue warning about any old ontologies that are not in the new system?
#if ont_new.nil?
#  warningStr = "WARNING: skipping ontology, no match in new REST system: #{ontStr}."
#  warnings.push warningStr
#  puts warningStr if DEBUG
#  next
#end

acronyms_common.each do |acronym|

  ont_old = onts_old_by_acronym[acronym]
  ont_new = onts_new_by_acronym[acronym]

  # TODO: use progress bar.


  # TODO: iterate through versions (submissions).
  #if ALL_ONTOLOGY_VERSIONS
  #  # Iterate over all the versions
  #end

  ontologyCount += 1
  ontStrData = [UI_URL, ont_old.ontologyId, ont_old.id, ont_old.internalVersionNumber, ont_old.abbreviation, ont_old.format]
  ontStr = sprintf("%s/%d (version: %5d, submission: %3d), %s (format: %s)", *ontStrData)
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


  # Retrieve the old metrics and assign values to a new metrics model.
  ont_old_metrics = RestHelper.ontology_metrics(ont_old.id)
  ontologyCountValid += 1
  m = LinkedData::Models::Metric.new()
  m.classes = ont_old_metrics.numberOfClasses
  m.individuals = ont_old_metrics.numberOfIndividuals
  m.properties = ont_old_metrics.numberOfProperties
  m.maxDepth = ont_old_metrics.maximumDepth
  m.maxChildCount = ont_old_metrics.maximumNumberOfSiblings
  m.averageChildCount = ont_old_metrics.averageNumberOfSiblings
  m.classesWithOneChild = ont_old_metrics.classesWithOneSubclass[0][:string].length
  m.classesWithMoreThan25Children = ont_old_metrics.classesWithMoreThanXSubclasses.length
  m.classesWithNoDefinition = ont_old_metrics.classesWithNoDocumentation.length
  # Ignore these metrics properties
  #ont_old_metrics.classesWithNoAuthor
  #ont_old_metrics.classesWithMoreThanOnePropertyValue

  # Assign the metrics to a submission version and save
  #m.submission = sub.id.to_s  # reverse property cannot be assigned
  m.id = sub.id + '/metrics'
  m.save if m.valid?
  sub.bring_remaining
  sub.metrics = m
  sub.save if sub.valid?

  $stdout.write "INFO: #{ontStr} ..."
  if not sub.valid?
    failures.push "FAILURE: #{ontStr}."
    #$stdout.write " OOPS: trying again, ontology #{ontStr} ..."
    #status = runMetrics(ont_old)  # returns 0 on failure, 1 on success
  else
    metricsCount += 1
  end
end


puts
puts warnings if not DEBUG
puts failures
puts "\n\nINFO: total ontology count: #{ontologyCount}."
puts "INFO: #{ontologyCountValid} candidate ontologies."
puts "INFO: updated metrics for #{metricsCount} ontologies."
puts
