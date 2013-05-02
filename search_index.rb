require_relative 'settings'

require 'logger'
require 'progressbar'

submissions = LinkedData::Models::OntologySubmission.where(summaryOnly: false, submissionStatus: {code: "RDF"})
pbar = ProgressBar.new("Indexing Ontologies for search", submissions.length)
logger = Logger.new("logs/indexing.log")
submissions.each do |s|
  begin
    s.index logger
  rescue Exception => e
    logger.error e
  end
  pbar.inc
end
