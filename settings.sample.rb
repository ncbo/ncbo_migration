REST_URL              = "http://rest.bioontology.org/bioportal"
API_KEY               = ""
DOWNLOAD_FILES        = true
ALL_ONTOLOGY_VERSIONS = false
PARSE_ONLY_LATEST     = true
REPOSITORY_FOLDER     = "./repo"
UMLS_DOWNLOAD_SITE    = "http://localhost/umls"
# MySQL host for users.
USERS_DB_HOST         = ""
USERS_DB_USERNAME     = ""
USERS_DB_PASSWORD     = ""
# MySQL host for OBS concept table.
OBS_DB_HOST           = ""
OBS_DB_USERNAME       = ""
OBS_DB_PASSWORD       = ""
# MySQL host for projects and reviews.
ROR_DB_HOST           = ""
ROR_DB_USERNAME       = ""
ROR_DB_PASSWORD       = ""
GOO_HOST              = "localhost"
GOO_PORT              = 9000
SEARCH_SERVER_URL     = "http://ncbo-dev-app-02.stanford.edu:8080/solr/"
ANNOTATOR_DICT_FILE   = "./dictionary.txt"
REDIS_HOST            = "localhost"
REDIS_PORT            = 6379

## DO NOT EDIT BELOW THIS LINE
# Configure ontologieS_linked_data
require "ontologies_linked_data"
require "ncbo_annotator"

repo = Kernel.const_defined?("REPOSITORY_FOLDER") ? REPOSITORY_FOLDER : "./repo"
LinkedData.config do |config|
  config.repository_folder = repo
  config.goo_host = GOO_HOST
  config.goo_port = GOO_PORT
  config.search_server_url = SEARCH_SERVER_URL
  config.redis_host = REDIS_HOST
  config.redis_port = REDIS_PORT
end

Annotator.config do |settings|
  settings.mgrep_dictionary_file = ANNOTATOR_DICT_FILE
  settings.stop_words_default_file = "./default_stop_words.txt"
end

#for mappings we need sort to a folder with enough space for
#intermediate files
$TMP_SORT_FOLDER = File.join(repo,"tmp_sort")
