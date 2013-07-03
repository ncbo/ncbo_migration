require_relative 'settings'

require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

require_relative 'helpers/rest_helper'
require 'pry'

DEBUG = true

# A utility to verify that data can be parsed as json strings
require 'json'
def valid_json? json_
  JSON.parse(json_)
  return true
rescue JSON::ParserError
  return false
end

# Create valid project parameters
default_project_params = {
    :acronym => nil,            # required
    :creator => nil,            # required, instance of user
    :created => DateTime.new,   # required, auto-set with lambda
    :updated => DateTime.new,   # required, auto-set with lambda
    :name => nil,               # required
    :description => nil,        # required
    :homePage => nil,           # required, must be URI
    :contacts => "",            # optional
    :institution => "",         # optional
    :ontologyUsed => [],        # optional, an array of LinkedData::Models::Ontology items
}


# utility functions to cleanup latin-1 strings in projects

# Monkey patch String to remove problematic characters
class String
  def strip_control_characters()
    self.chars.inject("") do |str, char|
      unless char.ascii_only? and (char.ord < 32 or char.ord == 127)
        str << char
      end
      str
    end
  end
  def strip_control_and_extended_characters()
    self.chars.inject("") do |str, char|
      if char.ascii_only? and char.ord.between?(32,126)
        str << char
      end
      str
    end
  end
end

def string_clean2utf8(s)
  return s.strip_control_and_extended_characters.encode('UTF-8').strip
end

def project2params(project)
  project_params = default_project_params
  project_params[:name] =  string_clean2utf8 project[:name]
  project_params[:contacts] = string_clean2utf8 project[:people]
  project_params[:created] = project[:created_at].to_datetime
  project_params[:updated] = project[:updated_at].to_datetime
  project_params[:description] = string_clean2utf8 project[:description]
  project_params[:institution] = string_clean2utf8 project[:institution]
  homePage = string_clean2utf8 project[:homepage]
  homePage = 'http://' + homePage unless homePage.start_with?('http://')
  project_params[:homePage] = RDF::IRI.new(homePage)
  return project_params
end


# Ensure we start with a clean slate.
begin
  LinkedData::Models::Project.all.each do |m|
      m.delete
  end
  if LinkedData::Models::Project.all.empty?
      puts "Cleared all prior projects from the triple store."
  end
rescue Exception => e
  puts "\n\nFailed to clear all prior projects from the triple store!\n\n"
  raise e
end

ont_lookup = RestHelper.ontologies

client = Mysql2::Client.new(
    host: ROR_DB_HOST,
    username: ROR_DB_USERNAME,
    password: ROR_DB_PASSWORD,
    encoding: "latin1",
    database: "bioportal")

projects = client.query('SELECT * FROM projects ORDER BY name, updated_at DESC;')

uses_query = "SELECT DISTINCT ontology_id FROM uses WHERE project_id = %project_id%;"

project_failures = {
    :acronym => {},
    :invalid => [],
    :no_user => [],
}
# Track project acronyms to validate unique values.
project_acronyms = {}

puts "Number of projects to migrate: #{projects.count}"
pbar = ProgressBar.new("Migrating", projects.count)
projects.each_with_index(:symbolize_keys => true) do |project, index|

  pbar.inc if not DEBUG

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
  userLD = LinkedData::Models::User.find(user.username).first
  if userLD.nil?
    project_failures[:no_user].push(project)
    next
  end

  project_params = project2params project
  project_params[:creator] = userLD

  # Create a unique acronym for each project.
  # Hard code an acronym for 'Evidence Ontology' to avoid a conflict with 'Electrophysiology Ontology'
  if project[:name] == 'Evidence Ontology'
    project_params[:acronym] = 'ECO'  # From description
  else
    project_params[:acronym] = nil
  end
  name = project[:name].strip
  if not name.include?(' ')
    # If there are no spaces, use the entire project name as the acronym.
    project_params[:acronym] = name
  else
    if project_params[:acronym].nil?
      # Look for an acronym surrounded by '()'
      # e.g.: Resource of Asian Primary Immunodeficiency Diseases (RAPID)
      m = /\(.*\)/.match(name)
      if not m.nil?
        # Assume we can work with the first match.
        project_params[:acronym] = m[0].delete('(').delete(')').gsub(/[[:space:]]/,'')
        project_params[:name] = name.sub(m[0],'').strip
      end
    end
    if project_params[:acronym].nil?
      # Look for 'acronym:'
      # e.g.: NViz: A Visualization Tool for Refining Mappings between Biomedical Ontologies
      m = /\b.*:/.match(name)
      if not m.nil?
        # Assume we can work with the first match.
        project_params[:acronym] = m[0].delete(':').gsub(/[[:space:]]/,'')
        project_params[:name] = name.sub(m[0],'').strip
      end
    end
    if project_params[:acronym].nil?
      # Look for 'acronym -'
      # e.g.: Pandora - Protein ANnotation Diagram ORiented Analysis
      l = name.strip.split(/\W+-\W+/)
      if l.size > 1
        a = l.min_by{|s| s.strip.size }.strip
        r = name.gsub(a, '').gsub(/\W+-\W+/,'').strip
        project_params[:acronym] = a
        project_params[:name] = r
      end
      # Replaced this regex match with the alternate method above, because project
      # names can place the acronym at the beginning or the end of the name.
      #m = /\b.*-/.match(name)
      #if not m.nil?
      #  # Assume we can work with the first match.
      #  project_params[:acronym] = m[0].delete('-').gsub(/[[:space:]]/,'')
      #  project_params[:name] = name.sub(m[0],'').strip
      #end
    end
    if project_params[:acronym].nil? and name.length < 16
      # If the name is less than 16 characters, replace space with underscore
      project_params[:acronym] = name.gsub(/[[:space:]]/,'_')
    end
    if project_params[:acronym].nil?
      # Take the first letter of each word and combine.
      # e.g.: Multiscale Ontology for Skin Physiology becomes MOSP
      #a = name.gsub(/(?<F>\b[[:upper:]])(?<L>.*?\b)/,'\k<F>').gsub(/[[:lower:]]/,'').gsub(/\W/,'')
      #a = name.gsub(/(?<F>\b.)(?<L>.*?\b)/,'\k<F>').gsub(/[[:lower:]]/,'').gsub(/\W/,'')
      a = name.gsub(/(?<F>\b.)(?<L>.*?\b)/,'\k<F>').gsub(/\W/,'').upcase
      project_params[:acronym] = a
    end
  end
  if project_params[:acronym].nil?
    # Failed to set a project acronym.
    project_failures[:acronym][project[:id]] = [project, project_params]
    next
  end
  # validate acronym is unique.
  if project_acronyms.keys.include?(project_params[:acronym])
    # Failed to set a unique project acronym.
    project_failures[:acronym][project[:id]] = project
    if DEBUG
      puts
      puts 'DUPLICATE: ' + project_params[:acronym] + ' => ' + project.inspect
      puts 'CONFLICTS WITH: ' + project_acronyms[project_params[:acronym]].inspect
    end
    next
  else
    project_acronyms[project_params[:acronym]] = project
  end

  # Get the project ontologies.
  project_params[:ontologyUsed] = []
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
    ontLD = LinkedData::Models::Ontology.find(ontMatch.abbreviation).first
    if ontLD.nil?
      # Abbreviation failed, try the ontology display label (name).
      ontLD = LinkedData::Models::Ontology.where(:name => ontMatch.displayLabel).to_a
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
if DEBUG
  puts "Project migration failures (in the order failures are evaluated), if any:"
  #if not project_failures[:acronym].keys.empty?
  #  puts
  #  puts "Projects with faulty acronyms:"
  #  project_failures[:acronym].each {|k,v| puts "project-id: #{k}; project-SQL: #{v}" }
  #end
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
end

