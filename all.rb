require_relative 'settings'
require 'ontologies_linked_data'

# Require migrations in the order they need to run
# For example, ontologies requires users, categories, and groups
require_relative 'users'
require_relative 'categories'
require_relative 'groups'
require_relative 'ontologies'
require_relative 'views'
require_relative 'reviews'
require_relative 'projects'
require_relative 'notes'
require_relative 'provisional_classes'