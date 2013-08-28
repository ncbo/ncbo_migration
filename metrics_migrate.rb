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

def count_classes_with(classes, total_classes)
  # Parse the classesWith{stuff} properties (it's a mess!)
  # Example data
  #classesWithNoDocumentation=[{:string=>"limitpassed:10881"}]
  #classesWithMoreThanOnePropertyValue=[""]
  #classesWithOneSubclass=[
  #  {
  #    :string=> ["CHEBI:10033", "CHEBI:10036"]
  #  }
  #]
  #classesWithMoreThanXSubclasses=[
  #  {
  #    :entry=>[
  #      {:string=>["CHEBI:46848", 61]}, {:string=>["CHEBI:50994", 69]}, {:string=>["CHEBI:37734", 27]}
  #    ]
  #  }
  #]
  # classesWith{stuff} is always a list of stuff, even if it has only one item.
  count = 0
  classes.each do |c|
    # There could be an empty string in the list, which can be ignored
    next if (c.instance_of?(String) && c == '')
    if ( c.instance_of?(Hash) && c.include?(:string) )
      obj = c[:string]
      if obj.instance_of?(Array)
        if obj.all? {|e| e.instance_of? String }
          # This is likely a list of all the class short IDs.
          count += obj.length
        end
        # else?  What else could this data structure contain?
      end
      if obj.instance_of?(String)
        obj.include?('limitpassed') and count += obj.split(':').last.to_i
        obj.include?('alltriggered') and count += total_classes
      end
    end
    # Handle classesWithMoreThanXSubclasses
    if ( c.instance_of?(Hash) && c.include?(:entry) )
      obj = c[:entry]
      if obj.instance_of?(Array)
        if obj.all? {|e| e.instance_of? Hash }
          count += obj.length
        end
        # else?  What else could this data structure contain?
      end
    end
  end
  raise RangeError, 'Count is larger than total classes' unless count <= total_classes
  return count
end

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

  ont_old_versions = RestHelper.ontology_versions(ont_old.ontologyId)
  ont_old_versions.each do |ont_ver|

    ontologyCount += 1
    ontStrData = [UI_URL, ont_ver.ontologyId, ont_ver.id, ont_ver.internalVersionNumber, ont_ver.abbreviation, ont_ver.format]
    ontStr = sprintf("%s/%d (version: %5d, submission: %3d), %s (format: %s)", *ontStrData)
    #if not ont_ver.format.start_with?('OWL')
    #    warningStr = "WARNING: skipping ontology, format != OWL: #{ontStr}."
    #    warnings.push warningStr
    #    puts warningStr if DEBUG
    #    next
    #end
    if ont_ver.isMetadataOnly == 1
      # metadata only ontologies also have statusId = 5.
      warningStr = "WARNING: skipping ontology, metadata only: #{ontStr}."
      warnings.push warningStr
      puts warningStr if DEBUG
      next
    end
    if ont_ver.statusId != 3
      warningStr = "WARNING: skipping ontology, statusId != 3 (#{ont_ver.statusId}): #{ontStr}."
      warnings.push warningStr
      puts warningStr if DEBUG
      next
    end
    # Retrieve this ontology version metrics and check they have been calculated.
    ont_ver_metrics = RestHelper.ontology_metrics(ont_ver.id)
    if ont_ver_metrics.numberOfClasses.nil?
      warningStr = "WARNING: skipping ontology version, no metrics in old REST system: #{ontStr}."
      warnings.push warningStr
      puts warningStr if DEBUG
      next
    end
    # Determine whether new REST API contains an ontology submission matching ont_ver.internalVersionNumber
    ont_new_submissionIds = ont_new.submissions.map {|s| s.submissionId }
    if not ont_new_submissionIds.include? ont_ver.internalVersionNumber
      warningStr = "WARNING: skipping ontology, no submission match in new REST system: #{ontStr}."
      warnings.push warningStr
      puts warningStr if DEBUG
      next
    end
    # Get the matching submission and determine whether it already has metrics available
    subIndex = ont_new_submissionIds.index(ont_ver.internalVersionNumber)
    sub = ont_new.submissions[subIndex]
    if not sub.metrics.nil?
      warningStr = "WARNING: skipping ontology, submission already has metrics in new REST system: #{ontStr}."
      warnings.push warningStr
      puts warningStr if DEBUG
      next
    end
    # Double check, try to find an orphaned metric object!
    metricId = sub.id + '/metrics'
    m = LinkedData::Models::Metric.find(metricId).first
    if not m.nil?
      warningStr = "WARNING: skipping ontology, submission already has metrics in new REST system: #{ontStr}."
      warnings.push warningStr
      puts warningStr if DEBUG
      next
    else
      # Maybe delete this?
    end
    # Assign the old metrics values to a new metrics model.
    # Ignore these old metrics properties:
    #ont_ver_metrics.classesWithNoAuthor
    #ont_ver_metrics.classesWithMoreThanOnePropertyValue
    ontologyCountValid += 1
    m = LinkedData::Models::Metric.new()
    m.id = metricId
    m.classes = ont_ver_metrics.numberOfClasses
    m.individuals = ont_ver_metrics.numberOfIndividuals
    m.properties = ont_ver_metrics.numberOfProperties
    m.maxDepth = ont_ver_metrics.maximumDepth
    m.maxChildCount = ont_ver_metrics.maximumNumberOfSiblings
    m.averageChildCount = ont_ver_metrics.averageNumberOfSiblings
    # Handle the classesWith{stuff} data, which can be various data structures.
    # CHEBI example data: ont_ver_metrics.classesWithOneSubclass[0][:string].length
    m.classesWithOneChild = count_classes_with( ont_ver_metrics.classesWithOneSubclass, m.classes )
    # CHEBI example data: ont_ver_metrics.classesWithMoreThanXSubclasses[0][:entry].length
    m.classesWithMoreThan25Children = count_classes_with( ont_ver_metrics.classesWithMoreThanXSubclasses, m.classes )
    # CHEBI example data: ont_ver_metrics.classesWithNoDocumentation[0][:string].split(':').last.to_i
    m.classesWithNoDefinition = count_classes_with( ont_ver_metrics.classesWithNoDocumentation, m.classes )
    # Assign the metrics to a submission version and save
    #m.submission = sub.id.to_s  # reverse property cannot be assigned
    m.save if m.valid?
    sub.bring_remaining
    sub.metrics = m
    sub.save if sub.valid?
    if not sub.valid?
      failures.push "FAILURE: #{ontStr}"
      #$stdout.write " OOPS: trying again, ontology #{ontStr} ..."
      #status = runMetrics(ont_ver)  # returns 0 on failure, 1 on success
    else
      $stdout.write "SUCCESS: #{ontStr}"
      metricsCount += 1
    end
  end
end

puts
puts warnings if not DEBUG
puts failures
puts "\n\nINFO: total ontology count: #{ontologyCount}."
puts "INFO: #{ontologyCountValid} candidate ontologies."
puts "INFO: updated metrics for #{metricsCount} ontologies."
puts
