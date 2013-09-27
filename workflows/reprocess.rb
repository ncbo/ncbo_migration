require_relative '../settings'

require 'logger'
require 'progressbar'

# An array of acronyms to restrict parsing to these particular ontologies
acronyms = ["CCO"]

submissions = []
acronyms.each do |acr|
  submissions << LinkedData::Models::Ontology.find(acr).first.latest_submission(status: :any)
end

puts "", "Parsing #{submissions.length} submissions..."
pbar = ProgressBar.new("Parsing", submissions.length)
FileUtils.mkdir_p("./parsing")
submissions.each do |s|
  s.bring_remaining
  s.bring(ontology: [:acronym])
  log_file = File.open("./parsing/parsing_#{s.ontology.acronym}.log", "w")
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG
  begin
    binding.pry
    s.process_submission(logger,
                          process_rdf: true, index_search: false,
                          run_metrics: false, reasoning: true)
  rescue Exception => e
    binding.pry
  end
  pbar.inc
end
