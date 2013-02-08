require 'cgi'
require 'ostruct'
require 'json'
require 'open-uri'
require 'recursive-open-struct'

require_relative '../settings'

class RestHelper
  CACHE = {}

  def self.get_json(path)
    if CACHE[path]
      json = CACHE[path]
    else
      apikey = path.include?("?") ? "&apikey=#{API_KEY}" : "?apikey=#{API_KEY}"
      begin
        json = open("#{REST_URL}#{path}#{apikey}", { "Accept" => "application/json" }).read
      rescue OpenURI::HTTPError => http_error
        raise http_error
      rescue Exception => e
        binding.pry
      end
      json = JSON.parse(json, :symbolize_names => true)
      CACHE[path] = json
    end
    json
  end
  
  def self.get_json_as_object(json)
    if json.kind_of?(Array)
      return json.map {|e| RecursiveOpenStruct.new(e)}
    elsif json.kind_of?(Hash)
      return RecursiveOpenStruct.new(json)
    end
    json
  end
  
  def self.user(user_id)
    json = get_json("/users/#{user_id}")
    get_json_as_object(json[:success][:data][0][:userBean])
  end
  
  def self.category(cat_id)
    self.categories.each {|cat| return cat if cat.id.to_i == cat_id.to_i}
  end
  
  def self.group(group_id)
    self.groups.each {|grp| return grp if grp.id.to_i == group_id.to_i}
  end
  
  def self.ontologies
    get_json_as_object(get_json("/ontologies")[:success][:data][0][:list][0][:ontologyBean])
  end
  
  def self.categories
    get_json_as_object(get_json("/categories")[:success][:data][0][:list][0][:categoryBean])
  end
  
  def self.groups
    get_json_as_object(get_json("/groups")[:success][:data][0][:list][0][:groupBean])
  end
  
  def self.concept(ontology_id, concept_id)
    json = get_json("/concepts/#{ontology_id}?conceptid=#{CGI.escape(concept_id)}")
    get_json_as_object(json[:success][:data][0][:classBean])
  end
    
  def self.safe_acronym(acr)
    CGI.escape(acr.downcase.gsub(" ", "_"))
  end
  
  def self.new_iri(iri)
    return nil if iri.nil?
    RDF::IRI.new(iri)
  end
  
  def self.lookup_property_uri(ontology_id, property_id)
    property_id = property_id.to_s
    return nil if property_id.nil? || property_id.eql?("")
    return property_id if property_id.start_with?("http://") || property_id.start_with?("https://")
    begin
      concept(ontology_id, property_id).fullId
    rescue OpenURI::HTTPError => http_error
      return nil if http_error.message.eql?("404 Not Found")
    end
  end
  
end