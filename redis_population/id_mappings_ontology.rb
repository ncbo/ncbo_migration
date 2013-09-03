require_relative '../settings'
require_relative '../helpers/rest_helper'

require 'pry'
require 'progressbar'
require 'redis'

redis = Redis.new(host: LinkedData.settings.redis_host, port: LinkedData.settings.redis_port)

KEY_STORAGE = "old:onts:keys"

# Delete old data
puts "Deleting old redis keys"
keys = redis.smembers(KEY_STORAGE)
puts "Deleting #{keys.length} ontology mapping entries"
keys.each_slice(500_000) {|chunk| redis.del chunk}
redis.del KEY_STORAGE

onts_and_views = RestHelper.ontologies + RestHelper.views
puts "Creating id mappings for #{onts_and_views.length} ontologies and views"

pbar = ProgressBar.new("Mapping", onts_and_views.length)
redis.pipelined do
  onts_and_views.each do |o|
    acronym = RestHelper.safe_acronym(o.abbreviation)

    # Virtual id from acronym
    redis.set "old:acronym_from_virtual:#{o.ontologyId}", acronym
    redis.sadd KEY_STORAGE, "old:acronym_from_virtual:#{o.ontologyId}"
    
    # Acronym from virtual id
    redis.set "old:virtual_from_acronym:#{acronym}", o.ontologyId
    redis.sadd KEY_STORAGE, "old:virtual_from_acronym:#{acronym}"
    
    # This call works for views and ontologies (gets all versions from related virtual id)
    versions = RestHelper.ontology_versions(o.ontologyId)
    versions.each do |ov|
      # Version to virtual mapping
      redis.set "old:virtual_from_version:#{ov.id}", o.ontologyId
      redis.sadd KEY_STORAGE, "old:virtual_from_version:#{ov.id}"
    end
    
    pbar.inc
  end
end
