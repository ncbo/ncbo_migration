require_relative 'settings'

require 'logger'
require 'progressbar'

#An example to patch RDF data

names=LinkedData::Utils::Namespaces
triples = []
triples << "<#{names.gen_sy}> <#{names.rdfs_subPropertyOf}> <#{names.skos_altLabel}> ."
triples << "<#{names.obo_sy}> <#{names.rdfs_subPropertyOf}> <#{names.skos_altLabel}> ."

triples << "<#{names.rdfs_comment}> <#{names.rdfs_subPropertyOf}> <#{names.skos_definition}> ."
triples << "<#{names.obo_def}> <#{names.rdfs_subPropertyOf}> <#{names.skos_definition}> ."
triples = triples.join "\n"

obo = LinkedData::Models::OntologyFormat.find("OBO")
obo_submissions = LinkedData::Models::OntologySubmission.where(hasOntologyLanguage: obo, summaryOnly: false, submissionStatus: {code: "RDF"})
puts "OBO ontologies parsed #{obo_submissions.length} patching up ..."
pbar = ProgressBar.new("Patching OBO ontologies ", obo_submissions.length)
obo_submissions.each do |sub|
  graph = sub.resource_id.value
  Goo.store.append_in_graph(triples, graph, SparqlRd::Utils::MimeType.turtle)
  pbar.inc
end
