require_relative '../settings'

require 'logger'
require 'progressbar'

# An array of acronyms to restrict parsing to these particular ontologies
acronyms = ["CCO"]

submissions = []
acronym.each |acr| do 
  submissions << LinkedData::Models::Ontology.find(acr).latest_submission(status: :any)
end
binding.pry

puts "", "Parsing #{submissions.length} submissions..."
pbar = ProgressBar.new("Parsing", submissions.length)
FileUtils.mkdir_p("./parsing")
submissions.each do |s|
  submissions.bring_remaining
  log_file = File.open("./parsing/parsing_#{os.ontology.acronym}.log", "w")
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG
  begin
    reasoning = !disable_reasoning_for.include?(os.ontology.acronym)
    os.process_submission(logger,
                          process_rdf: true, index_search: false,
                          run_metrics: false, reasoning: true)
end


ontologies_to_parse.each do |os|
  next if os.ontology.summaryOnly

  log_file = File.open("./parsing/parsing_#{os.ontology.acronym}.log", "w")
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG

  begin
    os.process_submission(logger,
                          process_rdf: true, index_search: false,
                          run_metrics: false, reasoning: reasoning)

  rescue Exception => e
    binding.pry
  end
  pbar.inc
end
