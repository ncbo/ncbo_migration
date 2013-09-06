require 'ncbo_resolver'

options = {
  redis_host: LinkedData.settings.redis_host,
  redis_port: LinkedData.settings.redis_port,
  api_key: API_KEY,
  rest_url: REST_URL
}
rest_helper = NCBO::Resolver::RestHelper.new(options)

# Make the constant point to the Resolver instance
# This keeps old code working, but we get RestHelper updated
# in a single place.
RestHelper = rest_helper