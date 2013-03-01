require_relative 'helpers/setup_ontologies_linked_data'
LinkedData::Models::Ontology.all.each {|o| o.load; o.delete rescue next}