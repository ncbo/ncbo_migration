require_relative '../settings'

require 'logger'
require 'progressbar'
require 'benchmark'

# clear the index
LinkedData::Models::Class.indexClear()
LinkedData::Models::Class.indexCommit()

submissions = LinkedData::Models::OntologySubmission.where(submissionStatus: [code: "RDF"]).include(:submissionId, ontology: LinkedData::Models::Ontology.attributes).all
pbar = ProgressBar.new("Indexing Ontologies for search", submissions.length)
logger = Logger.new("logs/indexing.log")
logger.info("Began indexing all ontologies...")
time = Benchmark.realtime do
  submissions.each do |s|
    begin
      s.process_submission(logger,
                           process_rdf: false, index_search: true,
                           run_metrics: false, process_annotator: false,
                           reasoning: false)
    rescue Exception => e
      logger.error e
    end
    pbar.inc
  end
end
logger.info("Completed indexing all ontologies in #{time/60} min.")

logger.info("Optimizing index...")
time = Benchmark.realtime do
  LinkedData::Models::Class.indexOptimize()
end
logger.info("Completed optimizing index in #{time} sec.")

