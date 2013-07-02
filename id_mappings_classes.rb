require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'pry'
require 'progressbar'
require 'redis'

only_these_ontologies = []
page_size = 2500
redis = Redis.new(host: LinkedData.settings.redis_host, port: LinkedData.settings.redis_port)

##
# Takes a URI and shortens it (takes off everything except the last fragment) according to NCBO rules.
# Only OBO format has special processing.
# The format can be obtained by doing ont.latest_submission.hasOntologyLanguage.acronym.to_s
def shorten_uri(uri, ont_format = "")
  uri = uri.to_s
  if ont_format.eql?("OBO")
    if uri.start_with?("http://purl.org/obo/owl/")
      last_fragment = uri.split("/").last.split("#")
      prefix = last_fragment[0]
      mod_code = last_fragment[1]
    elsif uri.start_with?("http://purl.obolibrary.org/obo/")
      last_fragment = uri.split("/").last.split("_")
      prefix = last_fragment[0]
      mod_code = last_fragment[1]
    elsif uri.start_with?("http://www.cellcycleontology.org/ontology/owl/")
      last_fragment = uri.split("/").last.split("#")
      prefix = last_fragment[0]
      mod_code = last_fragment[1]
    elsif uri.start_with?("http://purl.bioontology.org/ontology/")
      last_fragment = uri.split("/")
      prefix = last_fragment[-2]
      mod_code = last_fragment[-1]
    end
    short_id = "#{prefix}:#{mod_code}"
  else
    # Everything other than OBO
    uri_parts = uri.split("/")
    short_id = uri_parts.last
    short_id = short_id.split("#").last if short_id.include?("#")
  end
  short_id
end

# Delete old data
puts "Deleting old redis keys"
termKeys = redis.keys("old_to_new:uri_from_short_id:*")
chunks = (termKeys.length / 500_000.0).ceil
curr_chunk = 1
termKeys.each_slice(500_000) do |keys_chunk|
  puts "Deleting class keys chunk #{curr_chunk} of #{chunks}"
  redis.del(keys_chunk) unless keys_chunk.empty?
  curr_chunk += 1
end

# Figure out latest parsed submissions using all submissions
includes = [:submissionStatus, :hasOntologyLanguage, :submissionId, ontology: LinkedData::Models::Ontology.goo_attrs_to_load]
submissions = LinkedData::Models::OntologySubmission.where.include(includes).to_a
latest_submissions = {}
submissions.each do |sub|
  next unless sub.submissionStatus.parsed?
  next if !only_these_ontologies.empty? && !only_these_ontologies.include?(sub.ontology.acronym)
  latest_submissions[sub.ontology.acronym] ||= sub
  latest_submissions[sub.ontology.acronym] = sub if sub.submissionId > latest_submissions[sub.ontology.acronym].submissionId
end
latest_submissions = latest_submissions.values

puts "Creating class id mappings for #{latest_submissions.length} submissions"

pbar = ProgressBar.new("Mapping", latest_submissions.length)
latest_submissions.each do |sub|
  paging = LinkedData::Models::Class.where.include(:prefLabel).in(sub).read_only.page(1, page_size)
  
  pbar_pages = nil
  begin
    begin
      class_page = paging.all
      pbar_pages ||= ProgressBar.new("#{class_page.total_pages} #{sub.ontology.acronym}", class_page.total_pages)
    rescue
      # If page fails, skip to next ontology
      puts "Failed mapping classes for #{sub.ont.acronym}"
      page = nil
      next
    end
    
    redis.pipelined do
      class_page.each do |cls|
        short_id = shorten_uri(cls.id, sub.hasOntologyLanguage)
        redis.set "old_to_new:uri_from_short_id:#{sub.ontology.acronym}:#{short_id}", cls.id
      end
    end
    
    pbar_pages.inc
    
    page = class_page.next_page
    
    if page
      paging.page(page)
    end
  end while !page.nil?

  pbar.inc
end