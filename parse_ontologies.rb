require 'logger'
require 'progressbar'
require 'ontologies_linked_data'

only_parse = []


submissions = LinkedData::Models::OntologySubmission.where(submissionStatus: {code: "UPLOADED"}, summaryOnly: false)

errors = []
already_parsed_or_summary = []
ontologies_to_parse = []

if only_parse.empty?
  puts "Searching #{submissions.length} submissions for unparsed entries..."
  pbar = ProgressBar.new("Searching", submissions.length)
  submissions.each do |os|
    os.load
    os.ontology.load
    pbar.inc
  
    if os.parsed? || os.summaryOnly
      already_parsed_or_summary << os.acronym
      next
    end
  
    if !os.valid?
      errors << "#{os.acronym}, #{os.errors}"
      next
    end
  
    ontologies_to_parse << os
  end
else
  only_parse.each do |o|
    ont = LinkedData::Models::Ontology.find(o)
    ont.load unless ont.loaded?
    sub = ont.submissions.first
    ontologies_to_parse << sub.load
  end
end


FileUtils.mkdir_p("./parsing")

timeouts = []
labels = []

puts "Parsing #{ontologies_to_parse.length} submissions..."
pbar = ProgressBar.new("Parsing", ontologies_to_parse.length)
ontologies_to_parse.each do |os|
  os.ontology.load unless os.ontology.loaded?
  
  log_file = File.open("./parsing/parsing_#{os.ontology.acronym}.log", "w")
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG

  begin
    os.process_submission(logger)
  rescue Timeout::Error => timeout
    timeouts << "#{os.ontology.acronym}, #{os.submissionId}"
  rescue Exception => e
    if e.message.include?("Class model only allows one label. TODO: internationalization")
      labels << "#{os.ontology.acronym}, #{os.submissionId}"
    else
      errors << "#{os.ontology.acronym}\n#{e.message}\n#{e.backtrace}"
    end
  end

  pbar.inc
end

puts "", "Timeouts:", timeouts.join("\n")

puts "", "Only one label:", labels.join("\n")

puts "", "Errors:", errors.join("\n\n")
  