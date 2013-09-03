require_relative 'settings'
LinkedData::Models::Ontology.where.all.each {|o| o.delete}