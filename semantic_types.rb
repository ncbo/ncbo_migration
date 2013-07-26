
#############################################################
# !!!! This script gets required at the end of ontolgies.rb #
#############################################################

require_relative 'settings'
require_relative 'helpers/rest_helper'
require_relative 'helpers/ontology_helper'

LDModels =LinkedData::Models

sty_acr = "STY"
submissionId = 1
ontologyFile = "./umls_semantictypes.ttl"

sty = LDModels::Ontology.find(sty_acr).include(LDModels::Ontology.attributes).first
sty.bring(:submissions) if sty
if sty && sty.submissions.length > 0
  puts "Semantic Types already in the system - skipping parsing"
  ont_sub = sty.latest_submission 
  classes = LinkedData::Models::Class.in(ont_sub).include(:prefLabel)
                .read_only.to_a
  puts "Backend STY contains #{classes.length} classes"
  if classes.length < 100
    raise ArgumentError, 
      "Something might be wrong  STY Ontology - " +
      "only #{classes.length} classes"
  end
else

  umls = LDModels::OntologyFormat.find("UMLS").first
  if umls.nil?
    raise ArgumentError, 
            "UMLS format not found - unable to parse STY ont."
  end
  user = LDModels::User.find("msalvadores").first
  if user.nil?
    raise ArgumentError, 
            "User for STY not found - unable to parse STY ont."
  end

  ont = sty
  if ont.nil?
    ont = LDModels::Ontology.new(
              acronym: sty_acr,
              name: "Semantic Types Ontology", administeredBy: [user]).save
  end

  contact = LDModels::Contact.where(name: "bioportal",
		      email: "support@bioontology.org")
					.first
  if contact.nil?
    contact = LDModels::Contact.new(
		     name: "bioportal",
		     email: "support@bioontology.org")
    contact.save
  end

  ont_submision =  LDModels::OntologySubmission.new(
        submissionId: submissionId)
  ont_submision.contact = [contact]
  ont_submision.hasOntologyLanguage = umls
  ont_submision.ontology = ont
  ont_submision.submissionStatus = 
        LDModels::SubmissionStatus.where(:code => "UPLOADED").first

  uploadFilePath = LDModels::OntologySubmission.copy_file_repository(
                                      sty_acr,
                                      submissionId, 
                                      ontologyFile)
  ont_submision.uploadFilePath = uploadFilePath
  ont_submision.released = DateTime.now
  ont_submision.save
  FileUtils.mkdir_p("./logs")
  log_file = File.open("./logs/parsing_#{sty_acr}.log", "w")
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG
  ont_submision.process_submission(logger)
  classes = LinkedData::Models::Class.in(ont_submision)
                    .include(:prefLabel)
                    .read_only.to_a
  puts "STY parsed with #{classes.length} classes"
  log_file.close()
  if classes.length < 100
    raise ArgumentError, 
      "Something might be wrong with STY Ontology - " +
      "only #{classes.length} classes"
  end
end #if sty
