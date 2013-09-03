require_relative '../settings'

require 'logger'
require 'progressbar'

puts "Loading submissions ..."

BatchProcess = LinkedData::Mappings::BatchProcess

attributes = LinkedData::Models::OntologySubmission.attributes + [ontology: [:acronym]]
submissions = LinkedData::Models::OntologySubmission
                                         .where(submissionStatus: {code: "RDF"}, 
                                                summaryOnly: false)
                                         .include(attributes)
                                         .to_a


puts "Initial submission bulk #{submissions.length}"
only_mappings = []
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

puts "I am going to flush the mapping graphs"
puts "sure ? (type !!! to exit ctrl-D to continue)"
binding.pry

Goo.sparql_data_client.delete_graph(LinkedData::Models::Mapping.type_uri)
Goo.sparql_data_client.delete_graph(LinkedData::Models::TermMapping.type_uri)
Goo.sparql_data_client.delete_graph(LinkedData::Models::MappingProcess.type_uri)

acronyms_sorted = mappings_to_process.keys.sort
subp = ProgressBar.new("Processing",mappings_to_process.length)
acronyms_sorted.each do |acr|
    submission = mappings_to_process[acr]
    batch_triples = File.join([BatchProcess.mappings_ontology_folder(submission.ontology),
                                "batch_triples.nq"])
    if File.exist?(batch_triples)
      begin
        Goo.sparql_data_client.append_triples_from_file(
                      RDF::URI.new("http://bogus"), batch_triples, "text/x-nquads")
      rescue => e
        puts "Error uploading #{batch_triples}: #{e}"
      end
    end
    subp.inc
end
