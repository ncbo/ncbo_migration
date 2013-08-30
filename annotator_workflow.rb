require_relative 'settings'

require 'logger'
require 'progressbar'
require 'benchmark'
require 'ncbo_annotator'


annotator = Annotator::Models::NcboAnnotator.new
ontologies_for_sw_challenge=["NCIT","GAZ","NCBITAXON","MESH","HUGO", "VANDF",
  "GO","REXO","RCD", "MEDDRA", "OMIM", "FMA"]

begin
#  annotator.create_term_cache(ontologies_filter=ontologies_for_sw_challenge)
  annotator.generate_dictionary_file
rescue Exception => e
  puts "Error: #{e.message}\n#{e.backtrace.join("\t\n")}"
end
