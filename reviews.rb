require_relative 'settings'

require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

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

ont_lookup = RestHelper.ontologies

client = Mysql2::Client.new(host: ROR_DB_HOST, username: ROR_DB_USERNAME, password: ROR_DB_PASSWORD, database: "bioportal")
reviews = client.query('SELECT * from reviews order by ontology_id')

rating_query = <<-EOS
SELECT R.review_id, R.rating_type_id, T.name AS rating_type, R.value
FROM ratings R, rating_types T
WHERE R.rating_type_id = T.id
  AND R.review_id = %review_id%
ORDER BY R.rating_type_id;
EOS

review_failures = {
    :no_user => [],
    :no_ontology => [],
    :no_content => [],
    :test_content => [],
    :invalid => []
}

puts "Number of reviews to migrate: #{reviews.count}"
pbar = ProgressBar.new("Migrating", reviews.count)
reviews.each_with_index(:symbolize_keys => true) do |review, index|

  pbar.inc
  if review[:review].downcase.start_with?('test')
    review_failures[:test_content].push(review)
    next
  end

  #puts review.inspect
  # :id=>89,
  # :user_id=>39143,
  # :ontology_id=>"1658",
  # :review=>"",
  # :created_at=>2011-08-24 06:33:42 -0700,
  # :updated_at=>2011-08-24 06:33:42 -0700,
  # :project_id=>129

  # Get the review ratings.
  ratings = client.query(rating_query.gsub("%review_id%", review[:id].to_s))

  # If the review contains no text and no ratings, skip it.
  #if review[:review].empty? and ratings.count == 0
  # If the review contains no text (regardless of ratings, skip it).
  if review[:review].empty?
    review_failures[:no_content].push(review)
    next
  end

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
  if ontMatch.nil?
    review_failures[:no_ontology].push(review)
    next
  end

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
  if ontLD.nil?
    review_failures[:no_ontology].push(review)
    next
  end

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
  if userLD.nil?
    review_failures[:no_user].push(review)
    next
  end

  review_params = default_review_params
  review_params[:body] = review[:review]
  review_params[:creator] = userLD
  review_params[:created] = review[:created_at].to_datetime
  review_params[:updated] = review[:updated_at].to_datetime
  review_params[:ontologyReviewed] = ontLD

  ratings.each do |rating|
    case rating["rating_type"]
      when "Domain Coverage"
        review_params[:coverageRating] = rating["value"]
      when "Correctness"
        review_params[:correctnessRating] = rating["value"]
      when "Quality Of Content"
        review_params[:qualityRating] = rating["value"]
      when "Degree Of Formality"
        review_params[:formalityRating] = rating["value"]
      when "Documentation And Support"
        review_params[:documentationRating] = rating["value"]
      when "Usability"
        review_params[:usabilityRating] = rating["value"]
      else
        # Should never arrive here.
        binding.pry
    end
  end
  # Note: the data migration should ignore review[:project_id].

  revLD = LinkedData::Models::Review.new(review_params)
  if revLD.valid?
    revLD.save
  else
    review_failures[:invalid].push(review)
    puts "Review is invalid."
    puts "Original review: #{review.inspect}"
    puts "Migration errors: #{revLD.errors}"
  end

  # TODO: some simple checks on the saved model?
end

pbar.finish
puts
puts "Review migration failures (in the order failures are evaluated)."
puts
puts "Reviews starting with 'test' content:"
puts review_failures[:test_content]
puts
puts "Reviews with no text or ratings:"
puts review_failures[:no_content]
puts
puts "Reviews with no matching ontology:"
puts review_failures[:no_ontology]
puts
puts "Reviews with no matching user:"
puts review_failures[:no_user]
puts
puts "Reviews with invalid model data:"
puts review_failures[:invalid]

