require_relative '../settings'

require 'logger'
require 'progressbar'

def status_fixer
  metrics_st = LinkedData::Models::SubmissionStatus.find("METRICS").first
  LinkedData::Models::Ontology.where.include(:acronym).all.each do |ont|
    sub = ont.latest_submission(status: :rdf)
    next unless sub
    metrics_id = RDF::URI.new(sub.id.to_s + "/metrics")
    m = LinkedData::Models::Metric.find(metrics_id).first
    if m
      sub.bring_remaining
      if sub.submissionStatus.select { |x| x.id.to_s == metrics_st.id.to_s}.length == 0
        sub.add_submission_status(metrics_st)
        if sub.valid?
          binding.pry
          sub.save
        end
      end
    end
  end
end
status_fixer
binding.pry

SOLR_EPR = "ncbo-stg-app-19.stanford.edu:8080"
def get_solr_ont_acronyms()
  call = "http://#{SOLR_EPR}/solr/collection1/select"
  response = RestClient.get call, {:params => { 
    :q => "*:*",
    :group => "true",
    "group.field" => "submissionAcronym",
    :wt => "json",
    :rows => 2000
  }}
  response = JSON.load(response)
  return response["grouped"]["submissionAcronym"]["groups"].map {|x| x["groupValue"]}
end
def get_solr_ont_term_count(acronym)
  call = "http://#{SOLR_EPR}/solr/collection1/select"
  response = RestClient.get call, {:params => { 
    :q => "submissionAcronym:#{acronym}",
    :group => "true",
    "group.field" => "submissionAcronym",
    :wt => "json"
  }}
  response = JSON.load(response)
  return response["grouped"]["submissionAcronym"]["groups"].first["doclist"]["numFound"]
end

solr_acronyms = get_solr_ont_acronyms
solr_stats = {}
solr_acronyms.each do |acr|
  count = get_solr_ont_term_count(acr)
  puts "Acronym #{acr} solr count #{count}"
  solr_stats[acr] = count
end
binding.pry

puts "Linking #{LinkedData::Models::Metric.where.all.length} metric objects"

metrics_st = LinkedData::Models::SubmissionStatus.find("METRICS").first
index_st = LinkedData::Models::SubmissionStatus.find("INDEXED").first

LinkedData::Models::Ontology.where.include(:acronym).all.each do |ont|
  sub = ont.latest_submission(status: :rdf)
  if sub
    sub.bring_remaining
    metrics_id = RDF::URI.new(sub.id.to_s + "/metrics")
    m = LinkedData::Models::Metric.find(metrics_id).first
    if m && !sub.metrics
      sub.add_submission_status(metrics_st)
      sub.metrics=m
    else
      puts "Submission #{sub.id.to_s} with no metrics"
    end
    if solr_stats.include?(ont.acronym) && sub.submissionStatus.select { |x| x.id.to_s == index_st.id.to_s}.length == 0
      sub.add_submission_status(index_st)
    else
      puts "Submission #{sub.id.to_s} with no SOLR terms"
    end
    if sub.modified? && sub.valid?
      sub.save
    else
      binding.pry if sub.modified?
    end
  else
    ont.bring(:summaryOnly)
    if !ont.summaryOnly
      puts "No RDF submission for #{ont.id.to_s}"
    end
  end
end
