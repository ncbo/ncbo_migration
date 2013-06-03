require_relative 'settings'

require 'logger'
require 'progressbar'
require 'benchmark'
require 'ncbo_annotator'


annotator = Annotator::Models::NcboAnnotator.new

begin
  annotator.create_term_cache
  annotator.generate_dictionary_file
rescue Exception => e
  puts "Error: #{e.message}\n#{e.backtrace.join("\t\n")}"
end