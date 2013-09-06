require 'ncbo_resolver'

require_relative '../settings'
require_relative '../helpers/rest_helper'

options = {
  redis_host: LinkedData.settings.redis_host,
  redis_port: LinkedData.settings.redis_port,
  rest_helper: RestHelper
}
populator = NCBO::Resolver::Population::Ontologies.new(options)
populator.populate
