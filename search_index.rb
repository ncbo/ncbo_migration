require_relative 'settings'

require 'logger'
require 'progressbar'

submissions = LinkedData::Models::OntologySubmission.where(summaryOnly: false, submissionStatus: {code: "RDF"})
pbar = ProgressBar.new("Indexing Ontologies for search", obo_submissions.length)
submission.each do |s|
  s.index Logger.new("SOME FILE")
  pbar.inc
end
