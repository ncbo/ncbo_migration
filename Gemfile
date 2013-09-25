source 'https://rubygems.org'

gem 'mysql2'
gem 'recursive-open-struct'
gem 'progressbar'
gem 'pry'
gem 'rsolr'
gem 'redis'
gem 'ncbo_resolver', git: "https://github.com/ncbo/ncbo_resolver.git"
gem 'cube-ruby', require: "cube"

# NCBO gems (can be from a local dev path or from rubygems/git)
gemfile_local = File.expand_path("../Gemfile.local", __FILE__)
if File.exists?(gemfile_local)
  self.instance_eval(Bundler.read_file(gemfile_local))
else
  gem 'sparql-client', :git => 'https://github.com/ncbo/sparql-client.git'
  gem 'goo', :git => 'https://github.com/ncbo/goo.git'
  gem 'ontologies_linked_data', :git => 'https://github.com/ncbo/ontologies_linked_data.git'
  gem 'ncbo_annotator', :git => 'https://github.com/ncbo/ncbo_annotator.git'
  # Use the linked data client with default PROD triple store access (only during dev)
  #gem 'faraday-http-cache', :git => 'https://github.com/ncbo/faraday-http-cache.git'
  #gem 'ontologies_api_client', :git => 'https://github.com/ncbo/ontologies_api_ruby_client.git'
end
