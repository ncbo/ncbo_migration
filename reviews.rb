require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

require_relative 'settings'
require_relative 'helpers/rest_helper'
require 'pry'


default_review_params = {
    :creator => nil,
    :created => DateTime.new,
    :body => "",
    :ontologyReviewed => nil,
    :usabilityRating => 0,
    :coverageRating => 0,
    :qualityRating => 0,
    :formalityRating => 0,
    :correctnessRating => 0,
    :documentationRating => 0
}


client = Mysql2::Client.new(host: ROR_DB_HOST, username: ROR_DB_USERNAME, password: ROR_DB_PASSWORD, database: "bioportal")

reviews = client.query('SELECT * from reviews order by ontology_id')
ont_lookup = RestHelper.ontologies

puts "Number of reviews to migrate: #{reviews.count}"
pbar = ProgressBar.new("Migrating", reviews.count*2)
reviews.each_with_index(:symbolize_keys => true) do |review, index|

  pbar.inc
  next if review[:review].empty?
  next if review[:review].downcase.start_with?('test')

  #puts review.inspect
  # :id=>89,
  # :user_id=>39143,
  # :ontology_id=>"1658",
  # :review=>"",
  # :created_at=>2011-08-24 06:33:42 -0700,
  # :updated_at=>2011-08-24 06:33:42 -0700,
  # :project_id=>129

  # lookup ontology in REST service data.
  ontMatch = nil
  ont_lookup.each do |o|
    if o.ontologyId == review[:ontology_id].to_i
      #puts "matched ontologyId = #{o.ontologyId}"
      ontMatch = o
      break
    elsif o.id == review[:ontology_id].to_i
      # Some reviews use the ontology version number in the :ontology_id field.
      #puts "matched id = #{o.id}"
      ontMatch = o
      break
    elsif o.displayLabel == review[:ontology_id]
      # Some reviews use the ontology name in the :ontology_id field.
      #puts "matched displayLabel = #{o.displayLabel}"
      ontMatch = o
      break
    end
  end
  # Move on if the review ontology is not found in the REST service data.
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
  # Move on if the review ontology is not found in the triple store data.
  next if ontLD.nil?

  # lookup user in REST service data.
  user = nil
  begin
    user = RestHelper.user(review[:user_id])
  rescue Exception => e
    # Move on when there is no user for the review?
  end
  next if user.nil?
  # Try to find this user in the triple store.
  userLD = LinkedData::Models::User.find(user.username)
  next if userLD.nil?


  review_params = default_review_params
  review_params[:body] = review[:review]
  review_params[:created] = review[:updated_at].to_datetime
  review_params[:creator] = userLD
  review_params[:ontologyReviewed] = ontLD
  revLD = LinkedData::Models::Review.new(review_params)


  # TODO: figure out how to handle review[:project_id] ?

  if revLD.valid?
    revLD.save
  else
    puts "Review is invalid."
    puts "Original review: #{review.inspect}"
    puts "Migration errors: #{revLD.errors}"
  end

  # Some simple checks?
end

pbar.finish
