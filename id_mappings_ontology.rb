require_relative 'settings'
require_relative 'helpers/rest_helper'

require 'pry'
require 'progressbar'
require 'redis'

redis = Redis.new(host: LinkedData.settings.redis_host, port: LinkedData.settings.redis_port)

# Delete old data
puts "Deleting old redis keys"
key_prefix = ["ri:acronym_from_virtual:", "ri:virtual_from_acronym:", "ri:virtual_from_version:"]
key_prefix.each do |key|
  keys = redis.keys("#{key}*")
  redis.del(keys) unless keys.empty?
end

onts_and_views = RestHelper.ontologies + RestHelper.views
puts "Creating id mappings for #{onts_and_views.length} ontologies and views"

pbar = ProgressBar.new("Mapping", onts_and_views.length)
redis.pipelined do
  onts_and_views.each do |o|
    acronym = RestHelper.safe_acronym(o.abbreviation)

    # Virtual id from acronym
    redis.set "ri:acronym_from_virtual:#{o.ontologyId}", acronym
    
    # Acronym from virtual id
    redis.set "ri:virtual_from_acronym:#{acronym}", o.ontologyId
    
    # This call works for views and ontologies (gets all versions from related virtual id)
    versions = RestHelper.ontology_versions(o.ontologyId)
    versions.each do |ov|
      # Version to virtual mapping
      redis.set "ri:virtual_from_version:#{ov.id}", o.ontologyId
    end
    
    pbar.inc
  end
end
