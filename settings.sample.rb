REST_URL              = "http://rest.bioontology.org/bioportal"
API_KEY               = ""
DOWNLOAD_FILES        = true
ALL_ONTOLOGY_VERSIONS = false
REPOSITORY_FOLDER     = "./repo"
UMLS_DOWNLOAD_SITE    = "http://localhost/umls"
# MySQL host for users.
USERS_DB_HOST         = ""
USERS_DB_USERNAME     = ""
USERS_DB_PASSWORD     = ""
# MySQL host for projects and reviews.
ROR_DB_HOST           = ""
ROR_DB_USERNAME       = ""
ROR_DB_PASSWORD       = ""
GOO_HOST              = "localhost"
GOO_PORT              = 9000

## DO NOT EDIT BELOW THIS LINE
# Configure ontologieS_linked_data
require "ontologies_linked_data"
repo = Kernel.const_defined?("REPOSITORY_FOLDER") ? REPOSITORY_FOLDER : "./repo"
LinkedData.config do |config|
  config.repository_folder = repo
  config.goo_host = GOO_HOST
  config.goo_port = GOO_PORT
end
