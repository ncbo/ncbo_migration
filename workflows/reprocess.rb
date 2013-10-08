require_relative '../settings'

require 'logger'
require 'progressbar'

# An array of acronyms to restrict parsing to these particular ontologies

def get_obo_submissions
  subs = []
  LinkedData::Models::Ontology.where.include(:acronym, :summaryOnly).all.each do |ont|
    if !ont.summaryOnly
      sub = ont.latest_submission(status: :any)
      if sub
        sub.bring(:hasOntologyLanguage)
        if sub.hasOntologyLanguage.obo?
          subs << sub
        end
      else
        puts "OBO ontology with no submissions #{ont.id.to_s}"
      end
    end
  end
  return subs
end

submissions = []
acronyms = ["CCO"]
acronyms.each do |acr|
  submissions << LinkedData::Models::Ontology.find(acr).first.latest_submission(status: :any)
end
#submissions = get_obo_submissions

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
    s.process_submission(logger,
                          process_rdf: true, index_search: false,
                          run_metrics: false, reasoning: true)
  rescue Exception => e
    binding.pry
  end
  pbar.inc
end
