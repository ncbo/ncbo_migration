require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'logger'
require 'progressbar'

# Create new (and remove old) logfile
FileUtils.mkdir_p("./logs")
file = File.open('./logs/metrics_migrate.log', File::WRONLY | File::APPEND | File::CREAT)
logger = Logger.new(file)
logger.level = Logger::DEBUG

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
failures = []

def count_classes(classes, total_classes, ontStr)
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
  raise RangeError, "Count is larger than total classes for #{ontStr}" unless count <= total_classes
  return count
end

# Get all the ontology metadata in the old REST API production system
begin
  onts_old = RestHelper.ontologies
rescue => e
  logger.fatal e.message
  raise e
end
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
acronyms_missing = acronyms_old.difference acronyms_new
logger.warn { "old-REST ontologies not in new-REST: #{acronyms_missing.to_a}" }

puts ""
puts "Number of old-REST ontologies: #{acronyms_old.length}"
puts "Number of new-REST ontologies: #{acronyms_new.length}"
puts "Number of common ontologies: #{acronyms_common.length}"
pbar = ProgressBar.new("Migrating", acronyms_common.length*2)

acronyms_common.each do |acronym|

  ont_old = onts_old_by_acronym[acronym]
  ont_new = onts_new_by_acronym[acronym]
  ont_new_submission_ids = ont_new.submissions.map {|s| s.submissionId }

  ont_old_versions = [ont_old]
  begin
    versions = RestHelper.ontology_versions(ont_old.ontologyId)
    if versions.kind_of? Array                   # many versions
      ont_old_versions.concat versions
    elsif versions.kind_of? RecursiveOpenStruct  # one version
      ont_old_versions.push versions
    end
  rescue Exception => e
    puts 'ERROR: \n' + e.message
  end
  ont_old_versions.each do |ont_ver|

    ontologyCount += 1
    ontStrData = [UI_URL, ont_ver.ontologyId, ont_ver.id, ont_ver.internalVersionNumber, ont_ver.abbreviation, ont_ver.format]
    ontStr = sprintf("%s/%d (version: %5d, submission: %3d), %s (format: %s)", *ontStrData)
    #if not ont_ver.format.start_with?('OWL')
    #    logger.warn { "WARNING: skipping ontology, format != OWL: #{ontStr}." }
    #    next
    #end
    if ont_ver.isMetadataOnly == 1
      # metadata only ontologies also have statusId = 5.
      logger.warn { "WARNING: #{ontStr}; skipping ontology, metadata only." }
      next
    end
    if ont_ver.statusId != 3
      logger.warn { "WARNING: #{ontStr}; skipping ontology, statusId != 3 (#{ont_ver.statusId})." }
      next
    end
    # Retrieve this ontology version metrics and check they have been calculated.
    begin
      ont_ver_metrics = RestHelper.ontology_metrics(ont_ver.id)
    rescue => e
      logger.error { "Failed to get ontology version metrics: #{e.message}"}
      next
    end
    if ont_ver_metrics.numberOfClasses.nil?
      logger.warn { "WARNING: #{ontStr}; skipping ontology version, no metrics in old REST system." }
      next
    end
    # Determine whether new REST API contains an ontology submission matching ont_ver.internalVersionNumber
    if not ont_new_submission_ids.include? ont_ver.internalVersionNumber
      logger.warn { "WARNING: #{ontStr}; skipping ontology, no submission match in new REST system." }
      next
    end
    # Get the matching submission and determine whether it already has metrics available
    subIndex = ont_new_submission_ids.index(ont_ver.internalVersionNumber)
    sub = ont_new.submissions[subIndex]
    if not sub.metrics.nil?
      logger.warn { "WARNING: #{ontStr}; skipping ontology, submission already has metrics in new REST system." }
      next
    end
    # Double check, try to find an orphaned metric object!
    metricId = sub.id + '/metrics'
    m = LinkedData::Models::Metric.find(metricId).first
    if not m.nil?
      logger.warn { "WARNING: #{ontStr}; skipping ontology, submission already has metrics in new REST system." }
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
    begin
      # Handle the classesWith{stuff} data, which can be various data structures.
      # CHEBI example data: ont_ver_metrics.classesWithOneSubclass[0][:string].length
      m.classesWithOneChild = count_classes(ont_ver_metrics.classesWithOneSubclass, m.classes, ontStr)
      # CHEBI example data: ont_ver_metrics.classesWithMoreThanXSubclasses[0][:entry].length
      m.classesWithMoreThan25Children = count_classes(ont_ver_metrics.classesWithMoreThanXSubclasses, m.classes, ontStr)
      # CHEBI example data: ont_ver_metrics.classesWithNoDocumentation[0][:string].split(':').last.to_i
      m.classesWithNoDefinition = count_classes(ont_ver_metrics.classesWithNoDocumentation, m.classes, ontStr)
    rescue Exception => e
      # Don't save these metrics
      logger.error { 'ERROR: ' + e.message }
      next
    end
    # Assign the metrics to a submission version and save
    #m.submission = sub.id.to_s  # reverse property cannot be assigned
    m.save if m.valid?
    sub.bring_remaining
    sub.metrics = m
    sub.save if sub.valid?
    if not sub.valid?
      msg = "FAILURE: #{ontStr}: #{sub.error}"
      failures.push msg
      logger.error { msg }
    else
      logger.info { "SUCCESS: #{ontStr}" }
      metricsCount += 1
    end
  end
  pbar.inc
end
pbar.finish

puts
puts failures
puts "\n\nINFO: total ontology count: #{ontologyCount}."
puts "INFO: #{ontologyCountValid} candidate ontologies."
puts "INFO: updated metrics for #{metricsCount} ontologies."
puts "INFO: logged details are in #{file.path}"
puts
