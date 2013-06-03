require_relative 'settings'

require 'logger'
require 'progressbar'
require 'benchmark'
require 'ncbo_annotator'


annotator = Annotator::Models::NcboAnnotator.new
annotator.create_term_cache
annotator.generate_dictionary_file