require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

require_relative 'settings'
require 'pry'

client = Mysql2::Client.new(host: ROR_DB_HOST, username: ROR_DB_USERNAME, password: ROR_DB_PASSWORD, database: "bioportal")

reviews = client.query('SELECT * from reviews')

puts "Number of reviews to migrate: #{reviews.count}"
pbar = ProgressBar.new("Migrating", reviews.count*2)
reviews.each_with_index(:symbolize_keys => true) do |review, index|

  pbar.inc
  puts review.inspect
  next

  # Build review object
  new_attrs = {
    username: user[:username].strip,
    email: user[:email],
    firstName: user[:firstname],
    lastName: user[:lastname],
    created: DateTime.parse(user[:date_created].to_s),
    apikey: user[:apykey],
  }
  new_user = LinkedData::Models::User.new(new_user_attrs)
  new_user.attributes[:passwordHash] = user[:password]

  pbar.inc

  if r.valid?
    r.save
  else
    puts "User #{user[:username]} not valid: #{r.errors}"
  end

  # Some simple checks
  retrieved_user = LinkedData::Models::User.find(user[:username].strip)
  errors = []
  if retrieved_user.nil?
    errors << "ERRORS: #{user[:username]}"
    errors << "retrieval"
  end
  puts errors.join("\n") + "\n\n" unless errors.length <= 1
  pbar.inc
end

pbar.finish
