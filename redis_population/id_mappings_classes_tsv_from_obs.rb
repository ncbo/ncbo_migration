require 'ncbo_resolver'

require_relative '../settings'

options = {
  tsv_path: REPOSITORY_FOLDER + "/obs_classes.tsv",
  obs_host: OBS_DB_HOST,
  obs_username: OBS_DB_USERNAME,
  obs_password: OBS_DB_PASSWORD,
  redis_host: LinkedData.settings.redis_host,
  redis_port: LinkedData.settings.redis_port
}
populator = NCBO::Resolver::Population::Classes.new(options)
populator.to_csv