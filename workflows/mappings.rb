require_relative '../settings'

require 'logger'
require 'progressbar'

#USE CAREFULLY
if ENV["MAP_CLEAN"] && ENV["MAP_CLEAN"] == "true"
  puts "Cleaning mapping graphs ..."
  Goo.sparql_data_client.delete_graph(LinkedData::Models::Mapping.type_uri)
  Goo.sparql_data_client.delete_graph(LinkedData::Models::TermMapping.type_uri)
  Goo.sparql_data_client.delete_graph(LinkedData::Models::MappingProcess.type_uri)
  puts "Cleaning mapping cache ..."
  redis = Redis.new(
      :host => LinkedData.settings.redis_host,
      :port => LinkedData.settings.redis_port,
      :timeout => 50000)
  mappings = redis.keys("mappings:*")
  binding.pry
  mappings.each do |k|
    redis.del(k)
  end
  puts "Done cleaning"
end

FileUtils.mkdir_p("./logs")

only_mappings = []

puts "Loading submissions ..."
attributes = LinkedData::Models::OntologySubmission.attributes + [ontology: [:acronym]]
submissions = LinkedData::Models::OntologySubmission
                                         .where(submissionStatus: {code: "RDF"})
                                         .include(attributes)
                                         .to_a


puts "Initial submission bulk #{submissions.length}"

processes = [LinkedData::Mappings::Loom,
             LinkedData::Mappings::CUI, 
             LinkedData::Mappings::SameURI,
             LinkedData::Mappings::XREF]


mappings_to_process = {}
submissions.each do |s|
  next if !only_mappings.empty? && only_mappings.index(s.ontology.acronym) == nil
  if mappings_to_process[s.ontology.acronym]
    if mappings_to_process[s.ontology.acronym].submissionId < s.submissionId
     mappings_to_process[s.ontology.acronym] = s
    end
  else
    mappings_to_process[s.ontology.acronym] = s
  end
end

pairs_processed = Set.new
logger = Logger.new("logs/mappings.log")
#logger = Logger.new(STDOUT)
logger.info("start processing ontologies")
count = 0
acronyms_sorted = mappings_to_process.keys.sort
resume_after = nil
acronyms_sorted.each do |acr1|
  s1 = mappings_to_process[acr1]
  if resume_after
     if acr1 <= resume_after
       count += 1
       acronyms_sorted.each do |acr2|
         pairs_processed << [acr1,acr2].sort
       end
       next
     end
  end
  count += 1
  puts "#{count}/#{mappings_to_process.length} ontologies processed"
  subp = ProgressBar.new("[#{acr1}]",mappings_to_process.length)
  acronyms_sorted.each do |acr2|
    s2 = mappings_to_process[acr2]
    subp.inc
    next if acr1 == acr2
    if pairs_processed.include?([acr1,acr2].sort)
      binding.pry
      next
    end
    processes.each do |mapping_proc|
      if mapping_proc == LinkedData::Mappings::CUI
        next unless s1.hasOntologyLanguage.umls? && s2.hasOntologyLanguage.umls?
      end
      logger.info("Running #{mapping_proc.name}: [#{acr1}] -- [#{acr2}] ...")
      t0 = Time.now
      command_call = "bundle exec ruby workflows/mappings_pair.rb #{acr1} #{acr2} #{mapping_proc.name}"
      puts command_call
      #stdout,stderr,status = Open3.capture3(command_call)
      #logger.info(stdout)
      #logger.info(stderr)
      #if not status.success?
      #  puts "error running `#{command_call}`"
      #end
      #mapping_proc.new(s1.ontology,s2.ontology,logger).start()
      #logger.info("COMPLETED #{mapping_proc.name}: [#{acr1}] -- [#{acr2}] in #{Time.now - t0} sec.")
    end
    pairs_processed << [acr1,acr2].sort
  end
  subp.clear
  puts "Finished #{acr1}: #{LinkedData::Models::Mapping.where.all.length} mappings in the system"
end

puts "FINISHED SCRIPT"
