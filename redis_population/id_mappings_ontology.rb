require 'ncbo_resolver'

require_relative '../settings'
require_relative '../helpers/rest_helper'

options = {
  redis_host: RESOLVER_REDIS_HOST,
  redis_port: RESOLVER_REDIS_PORT,
  rest_helper: RestHelper
}
populator = NCBO::Resolver::Population::Ontologies.new(options)
populator.populate
