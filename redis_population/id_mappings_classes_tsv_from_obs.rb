require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

require_relative 'settings'
require_relative 'helpers/rest_helper'

client = Mysql2::Client.new(host: OBS_DB_HOST, username: OBS_DB_USERNAME, password: OBS_DB_PASSWORD, database: "obs_hibernate")

LIMIT = 100_000

count_concepts_query = <<-EOS
SELECT count(*) as concepts from obs_concept
EOS

concept_query = <<-EOS
SELECT local_concept_id as id, full_id as uri
FROM obs_concept
LIMIT #{LIMIT} OFFSET %offset%
EOS

# Get ontology information
$ID_MAPPER = {}
start = Time.now
onts_views = RestHelper.ontologies + RestHelper.views
onts_views.each do |o|
  $ID_MAPPER[o.ontologyId.to_i] = o.abbreviation
  versions = RestHelper.ontology_versions(o.ontologyId)
  versions = versions.is_a?(Array) ? versions : [versions]
  versions.each do |v|
    $ID_MAPPER[v.id.to_i] = o.abbreviation
  end
end
puts "Finished getting old ids in #{Time.now - start}s"

# Iterate over the concept records and output to file
offset = 0
count = client.query(count_concepts_query)
iterations = (count.first["concepts"] / LIMIT) + 1
file = File.new("./id_mappings_classes.tsv", "w+")
iterations.times do
  puts "Starting at record #{offset}"
  concepts = client.query(concept_query.sub("%offset%", offset.to_s))
  offset += LIMIT
  concepts.each do |concept|
    uri = concept["uri"]
    id = concept["id"]
    ont_id_boundry = id.index("/")
    ont_id = id[0..ont_id_boundry - 1].to_i
    short_id = id[(ont_id_boundry + 1)..-1]
    acronym = $ID_MAPPER[ont_id]
    file.write("#{acronym}\t#{short_id}\t#{uri}\n")
  end
end
file.close

