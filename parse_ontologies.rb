require_relative 'settings'

require 'logger'
require 'progressbar'

# An array of acronyms to restrict parsing to these particular ontologies
only_parse = []


submissions = LinkedData::Models::OntologySubmission.where(submissionStatus: {code: "UPLOADED"}).include(LinkedData::Models::OntologySubmission.attributes + [ontology: [:acronym, :summaryOnly]]).to_a

errors = []
already_parsed_or_summary = []
ontologies_to_parse = []

if only_parse.empty?
  puts "Searching #{submissions.length} submissions for unparsed entries..."
  pbar = ProgressBar.new("Searching", submissions.length)
  submissions.each do |os|
    pbar.inc
  
    if os.submissionStatus.parsed? || os.ontology.summaryOnly
      already_parsed_or_summary << os.ontology.acronym
      next
    end
  
    if !os.valid?
      binding.pry
      errors << "#{os.ontology.acronym}, #{os.errors}"
      next
    end
  
    ontologies_to_parse << os
  end
else
  only_parse.each do |o|
    ont = LinkedData::Models::Ontology.find(o).include(submissions: [ontology: [:acronym, :summaryOnly] ]).first
    sub = ont.submissions.first
    ontologies_to_parse << sub
  end
end


FileUtils.mkdir_p("./parsing")

timeouts = []
labels = []

puts "", "Parsing #{ontologies_to_parse.length} submissions..."
pbar = ProgressBar.new("Parsing", ontologies_to_parse.length)
ontologies_to_parse.each do |os|
  next if os.ontology.summaryOnly

  log_file = File.open("./parsing/parsing_#{os.ontology.acronym}.log", "w")
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG

  begin
    os.process_submission(logger,process_rdf=true,index_search=false,run_metrics=false)
  rescue Timeout::Error => timeout
    timeouts << "#{os.ontology.acronym}, #{os.submissionId}, #{timeout.backtrace.join("\n\t")}"
  rescue Exception => e
    if e.message.include?("Class model only allows one label. TODO: internationalization")
      labels << "#{os.ontology.acronym}, #{os.submissionId}"
    else
      errors << "#{os.ontology.acronym}\n#{e.message}\n#{e.backtrace}"
    end
  end

  pbar.inc
end

puts "", "Already parsed or summary:", already_parsed_or_summary.join("\n")

puts "", "Timeouts:", timeouts.join("\n")

puts "", "Only one label:", labels.join("\n")

puts "", "Errors:", errors.join("\n\n")
  
