require_relative 'settings'

require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

require_relative 'helpers/rest_helper'
require 'pry'

# Create valid project parameters
default_project_params = {
    :name => "",
    :acronym => "",
    :creator => nil,
    :created => DateTime.new,
    :contacts => "",
    :description => "",
    :homePage => "",
    :institution => "",
    :ontologyUsed => nil,
}

ont_lookup = RestHelper.ontologies

client = Mysql2::Client.new(host: ROR_DB_HOST, username: ROR_DB_USERNAME, password: ROR_DB_PASSWORD, database: "bioportal")
projects = client.query('SELECT * from projects order by id;')

uses_query = "SELECT DISTINCT ontology_id FROM uses WHERE project_id = %project_id%;"

project_failures = {
    :no_user => [],
    :invalid => []
}

puts "Number of projects to migrate: #{projects.count}"
pbar = ProgressBar.new("Migrating", projects.count)
projects.each_with_index(:symbolize_keys => true) do |project, index|

  pbar.inc

  #puts project.inspect
  # :id=>11,
  # :name=>"Protege",
  # :institution=>"",
  # :people=>"",
  # :homepage=>"http://protege.stanford.edu",
  # :description=>"ProtÃ©gÃ© is a free, open source ontology editor and knowledge-base framework",
  # :created_at=>2008-04-18 12:23:08 -0700,
  # :updated_at=>2009-04-28 17:06:39 -0700,
  # :user_id=>3

  # lookup user in REST service data.
  user = nil
  begin
    user = RestHelper.user(project[:user_id])
  rescue Exception => e
    # Move on when there is no user for the project?
  end
  next if user.nil?
  # Try to find this user in the triple store.
  userLD = LinkedData::Models::User.find(user.username)
  if userLD.nil?
    project_failures[:no_user].push(project)
    next
  end

  project_params = default_project_params
  project_params[:name] = project[:name].strip
  project_params[:creator] = userLD
  project_params[:contacts] = project[:people].strip
  project_params[:created] = project[:created_at].to_datetime
  project_params[:updated] = project[:updated_at].to_datetime
  project_params[:description] = project[:description].strip
  project_params[:institution] = project[:institution].strip
  homePage = project[:homepage].strip
  homePage = 'http://' + homePage unless homePage.start_with?('http://')
  project_params[:homePage] = homePage

  # TODO: create a unique acronym for each project?  For now, using project id.
  #If there are no spaces, use the entire project name as the acronym
  #If there are spaces
  # - look for an acronym surrounded by '()' - EG: Resource of Asian Primary Immunodeficiency Diseases (RAPID)
  # - look for 'acronym:' EG: NViz: A Visualization Tool for Refining Mappings between Biomedical Ontologies
  # - look for 'acronym - ' EG: Pandora - Protein ANnotation Diagram ORiented Analysis
  # - if the name is less than 16 characters, replace space with underscore EG: Mobile RadLex
  # - otherwise, take the first letter of each word and combine EG: Multiscale Ontology for Skin Physiology becomes MOSP
  #
  # For the cases where we find an acronym in the title, we should remove it, EG:
  # Resource of Asian Primary Immunodeficiency Diseases (RAPID)
  # becomes
  # Resource of Asian Primary Immunodeficiency Diseases

  project_params[:acronym] = project[:id].to_s

  # Get the project ontologies.
  project_params[:ontologyUsed] = []
  uses_ontologies = nil
  uses_ontologies = client.query(uses_query.gsub("%project_id%", project[:id].to_s))
  uses_ontologies.each do |use_ont|

    # lookup ontology in REST service data.
    ontMatch = nil
    ont_lookup.each do |o|
      if o.ontologyId == use_ont["ontology_id"].to_i
        # Matched the ontology virtual number.
        ontMatch = o
        break
      elsif o.id == use_ont["ontology_id"].to_i
        # Matched the ontology version number.
        ontMatch = o
        break
      end
    end
    # Move on if the project ontology is not found in the REST service data.
    next if ontMatch.nil?

    # Use the ontology abbreviation to lookup the matching ontology data in the triple store.
    ontLD = LinkedData::Models::Ontology.find(ontMatch.abbreviation)
    if ontLD.nil?
      # Abbreviation failed, try the ontology display label (name).
      ontLD = LinkedData::Models::Ontology.where :name => ontMatch.displayLabel
      if ontLD.empty?
        ontLD = nil
      else
        ontLD = ontLD[0] # assume there is only one ontology to be considered.
      end
    end
    # Move on if the project ontology is not found in the triple store data.
    next if ontLD.nil?
    # Add this ontology to the list of used ontologies in the project.
    project_params[:ontologyUsed].push(ontLD)
  end

  #binding.pry
  #exit if index > 5
  #next

  projectLD = LinkedData::Models::Project.new(project_params)
  if projectLD.valid?
    projectLD.save
  else
    project_failures[:invalid].push(project)
    puts "Project is invalid."
    puts "Original project: #{project.inspect}"
    puts "Migration errors: #{projectLD.errors}"
  end

  # TODO: some simple checks on the saved model?
end

pbar.finish
puts "Project migration failures (in the order failures are evaluated), if any:"
if not project_failures[:no_user].empty?
  puts
  puts "Projects with no matching user:"
  puts project_failures[:no_user]
end
if not project_failures[:invalid].empty?
  puts
  puts "Projects with invalid model data:"
  puts project_failures[:invalid]
end
