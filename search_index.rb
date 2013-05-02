require_relative 'settings'

require 'logger'
require 'progressbar'

submissions = LinkedData::Models::OntologySubmission.where(summaryOnly: false, submissionStatus: {code: "RDF"})
pbar = ProgressBar.new("Indexing Ontologies for search", submissions.length)

submissions.each do |s|
  s.index Logger.new("logs/indexing.log")
  pbar.inc
end
