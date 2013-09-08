require_relative '../settings'

require 'logger'
require 'progressbar'

acrA = ARGV[0]
acrB = ARGV[1]
mapping_process = ARGV[2]

processes = [LinkedData::Mappings::Loom,
             LinkedData::Mappings::CUI, 
             LinkedData::Mappings::SameURI,
             LinkedData::Mappings::XREF]

process = processes.select { |x| x.name == mapping_process}.first
ontologyA = LinkedData::Models::Ontology.find(acrA).first 
ontologyB = LinkedData::Models::Ontology.find(acrB).first 

logger = Logger.new(STDOUT)
process.new(ontologyA,ontologyB,logger).start()
logger.close
