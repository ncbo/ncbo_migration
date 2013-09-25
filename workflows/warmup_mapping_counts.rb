require_relative '../settings'

require 'logger'
require 'progressbar'

puts "running counts per ontology"
LinkedData::Mappings.mapping_counts_per_ontology
puts "done"
LinkedData::Models::Ontology.where.include(:acronym).all.each do |ont|
  puts "running counts ontology #{ont.id.to_s}"
  LinkedData::Mappings.mapping_counts_for_ontology(ont)
end
