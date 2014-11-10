require_relative '../settings'

require 'logger'
require 'progressbar'

LinkedData::Models::Ontology.where.include(:acronym).all.each do |o|
   latest = o.latest_submission
   next if latest.nil?
   puts "Migrating mappings for #{o.acronym}"
   mapping_triples = LinkedData::Mappings.migrate_rest_mappings(o.acronym)
   puts "mapping_triples #{mapping_triples.length}"
   if mapping_triples.length > 0
     mapping_triples = mapping_triples.join "\n"
     puts "appending to #{latest.id.to_s}"
     result = Goo.sparql_data_client.append_triples(
          latest.id, mapping_triples,
          mime_type="application/x-turtle")
   end
end
