require_relative 'settings'
LinkedData::Models::Ontology.all.each {|o| o.load; o.delete rescue next}