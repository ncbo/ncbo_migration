require_relative '../settings'

require 'logger'
require 'progressbar'

FileUtils.mkdir_p("./logs")
logger = Logger.new("logs/metrics_calculate.log")


puts "Loading submissions ..."
attributes = LinkedData::Models::OntologySubmission.attributes + [ontology: [:acronym]]
submissions = LinkedData::Models::OntologySubmission
                                         .where(submissionStatus: {code: "RDF"})
                                         .include(attributes)
                                         .to_a
metrics_to_process = {}
submissions.each do |s|
  if metrics_to_process[s.ontology.acronym]
    if metrics_to_process[s.ontology.acronym].submissionId < s.submissionId
     metrics_to_process[s.ontology.acronym] = s
    end
  else
    metrics_to_process[s.ontology.acronym] = s
  end
end

subp = ProgressBar.new("Calculating metrics", metrics_to_process.length)
acronyms_sorted = metrics_to_process.keys.sort
acronyms_sorted.each_index do |i|
  acr = acronyms_sorted[i]
  sub = metrics_to_process[acr]
  sub.bring_remaining
  t0 = Time.now
  puts "#{i}/#{acronyms_sorted.length} calculating metrics for #{acr}"
  begin
    sub.process_submission(logger,
                           process_rdf: false, index_search: false,
                           run_metrics: true, reasoning: false)
  rescue => e
    puts "error in metrics for #{acr}"
    puts e
    if !sub.valid?
      puts sub.errors
    end
  end
  puts "calculated metrics for #{acr} in #{Time.now - t0} sec."
  subp.inc
end

