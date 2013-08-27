require 'cgi'
require 'uri'
require 'ostruct'
require 'json'
require 'open-uri'
require 'recursive-open-struct'
require 'progressbar'
require 'net/http'
require 'redis'

require_relative '../settings'

class RestHelper
  REDIS = Redis.new(host: LinkedData.settings.redis_host, port: LinkedData.settings.redis_port)
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
  
  def self.views
    get_json_as_object(get_json("/views")[:success][:data][0][:list][0][:ontologyBean])
  end

  def self.provisional_classes
    json = get_json("/provisional?pagesize=1000")
    results = json[:success][:data][0][:page][:contents][:classBeanResultList][:classBean]
    get_json_as_object(results)
  end

  def self.ontology_views(virtual_id)
    json = get_json("/views/versions/#{virtual_id}")
    list = json[:success][:data][0][:list][0]
    final_list = []

    if (!list.empty?)
      list.each do |view_version_list|
        view_version_list[1].each do |version|
          next if version == ""
          version_list = version[:ontologyBean]

          if version_list.kind_of?(Array)
            version_list.each do |v|
              final_list << v
            end
          else
            final_list << version_list
          end
        end
      end
    end

    return get_json_as_object(final_list)
  end

  def self.ontology(version_id)
    get_json_as_object(get_json("/ontologies/#{version_id}")[:success][:data][0][:list][0][:ontologyBean])
  end
  
  def self.ontology_versions(virtual_id)
    get_json_as_object(get_json("/ontologies/versions/#{virtual_id}")[:success][:data][0][:list][0][:ontologyBean])
  end
  
  def self.ontology_metrics(version_id)
    get_json_as_object(get_json("/ontologies/metrics/#{version_id}")[:success][:data][:ontologyMetricsBean])
  end
  
  def self.latest_ontology(virtual_id)
    get_json_as_object(get_json("/virtual/ontology/#{virtual_id}")[:success][:data][0][:ontologyBean])
  end
  
  def self.latest_ontology?(version_id)
    ont = ontology(version_id)
    latest = latest_ontology(ont.ontologyId)
    ont.id.to_i == latest.id.to_i
  end
  
  def self.roots(version_id)
    relations = get_json_as_object(get_json("/concepts/#{version_id}/root")[:success][:data][0][:classBean][:relations][0][:entry])
    relations.each do |rel|
      return rel.list if rel.string.eql?("SubClass")
    end
  end
  
  def self.ontology_notes(virtual_id)
    json = get_json("/virtual/notes/#{virtual_id}?threaded=true&archived=true")
    json = json[:success][:data][0][:list][0].empty? ? [] : json[:success][:data][0][:list][0][:noteBean]
    get_json_as_object(json)
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
  
  def self.ontology_file(ontology_id)
    file, filename = get_file("#{REST_URL}/ontologies/download/#{ontology_id}?apikey=#{API_KEY}")
    
    matches = filename.match(/(.*?)_v.+?(?:\.([^.]*)$|$)/)
    filename = "#{matches[1]}.#{matches[2]}" unless matches.nil?
    
    return file, filename
  end
  
  def self.get_file(uri, limit = 10)
    raise ArgumentError, 'HTTP redirect too deep' if limit == 0

    uri = URI(uri) unless uri.kind_of?(URI)
    
    if uri.kind_of?(URI::FTP)
      file, filename = get_file_ftp(uri)
    else
      file = Tempfile.new('ont-rest-file')
      file_size = 0
      filename = nil
      http_session = Net::HTTP.new(uri.host, uri.port) rescue binding.pry
      http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http_session.use_ssl = (uri.scheme == 'https')
      http_session.start do |http|
        http.request_get(uri.request_uri, {"Accept-Encoding" => "gzip"}) do |res|
          if res.kind_of?(Net::HTTPRedirection)
            new_loc = res['location']
            if new_loc.match(/^(http:\/\/|https:\/\/)/)
              uri = new_loc
            else
              uri.path = new_loc
            end
            return get_file(uri, limit - 1)
          end
    
          raise Net::HTTPBadResponse.new("#{uri.request_uri}: #{res.code}") if res.code.to_i >= 400
          
          file_size = res.read_header["content-length"].to_i
          begin
            filename = res.read_header["content-disposition"].match(/filename=\"(.*)\"/)[1] if filename.nil?
          rescue Exception => e
            filename = LinkedData::Utils::Triples.last_iri_fragment(uri.request_uri) if filename.nil?
          end
          bar = ProgressBar.new(filename, file_size)
          bar.file_transfer_mode
          res.read_body do |segment|
            bar.inc(segment.size)
            file.write(segment)
          end
          
          if res.header['Content-Encoding'].eql?('gzip')
            uncompressed_file = Tempfile.new("uncompressed-ont-rest-file")
            file.rewind
            sio = StringIO.new(file.read)
            gz = Zlib::GzipReader.new(sio)
            uncompressed_file.write(gz.read())
            file.close
            file = uncompressed_file
          end
        end
      end
      file.close
    end
    
    return file, filename
  end
  
  def self.get_file_ftp(url)
    url = URI.parse(url) unless url.kind_of?(URI)
    ftp = Net::FTP.new(url.host, url.user, url.password)
    ftp.passive = true
    ftp.login
    filename = LinkedData::Utils::Triples.last_iri_fragment(url.path)
    tmp = Tempfile.new(filename)
    file_size = ftp.size(url.path)
    bar = ProgressBar.new(filename, file_size)
    bar.file_transfer_mode
    ftp.getbinaryfile(url.path) do |chunk|
      bar.inc(chunk.size)
      tmp << chunk
    end
    tmp.close
    return tmp, filename
  end
    
  def self.safe_acronym(acr)
    CGI.escape(acr.to_s.gsub(" ", "_"))
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

  ##
  # Using the combination of the short_id (EX: "TM122581") and version_id (EX: "42389"),
  # this will do a Redis lookup and give you the full URI. The short_id is based on
  # what is produced by the `shorten_uri` method and should match Resource Index localConceptId output.
  # In fact, doing localConceptId.split("/") should give you the parameters for this method.
  # Population of redis data available here:
  # https://github.com/ncbo/ncbo_migration/blob/master/id_mappings_classes.rb
  def self.uri_from_short_id(version_id, short_id)
    acronym = self.acronym_from_version_id(version_id)
    uri = REDIS.get("old_to_new:uri_from_short_id:#{acronym}:#{short_id}")

    if uri.nil? && short_id.include?(':')
      try_again_id = short_id.split(':').last
      uri = REDIS.get("old_to_new:uri_from_short_id:#{acronym}:#{try_again_id}")
    end
    uri
  end

  ##
  # Given a virtual id, return the acronym (uses a Redis lookup)
  # Population of redis data available here:
  # https://github.com/ncbo/ncbo_migration/blob/master/id_mappings_ontology.rb
  # @param virtual_id [Integer] the ontology version ID
  def self.acronym_from_virtual_id(virtual_id)
    REDIS.get("old_to_new:acronym_from_virtual:#{virtual_id}")
  end

  ##
  # Given a version id, return the acronym (uses a Redis lookup)
  # Population of redis data available here:
  # https://github.com/ncbo/ncbo_migration/blob/master/id_mappings_ontology.rb
  # @param version_id [Integer] the ontology version ID
  def self.acronym_from_version_id(version_id)
    virtual = REDIS.get("old_to_new:virtual_from_version:#{version_id}")
    self.acronym_from_virtual_id(virtual)
  end

  def self.uri?(string)
    uri = URI.parse(string)
    %w( http https ).include?(uri.scheme)
  rescue URI::BadURIError
    false
  rescue URI::InvalidURIError
    false
  end
end