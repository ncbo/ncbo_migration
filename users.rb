require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

require_relative 'settings'
require 'pry'

client = Mysql2::Client.new(host: USERS_DB_HOST, username: USERS_DB_USERNAME, password: USERS_DB_PASSWORD, database: "bioportal")

user_query = <<-EOS
SELECT * from ncbo_user
EOS

role_query = <<-EOS
SELECT r.`name` FROM ncbo_user_role ur
JOIN `ncbo_l_role` r ON ur.`role_id` = r.id
WHERE user_id = %user_id%
EOS

users = client.query(user_query)

puts "Number of users to migrate: #{users.count}"
pbar = ProgressBar.new("Migrating", users.count*2)
users.each_with_index(:symbolize_keys => true) do |user, index|
  # Build user object
  new_user_attrs = {
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
  
  # Assign roles
  roles = client.query(role_query.gsub("%user_id%", user[:id].to_s))
  new_roles = []
  roles.each(:symbolize_keys => true).each do |role|
    role = LinkedData::Models::Users::Role.find(role[:name].gsub("ROLE_", ""))
    new_roles << role
  end
  new_roles = LinkedData::Models::Users::Role.default if new_roles.length < 1
  new_user.role = new_roles
  
  if new_user.valid?
    new_user.save
  else
    puts "User #{user[:username]} not valid: #{new_user.errors}"
  end
  
  # Some simple checks
  retrieved_user = LinkedData::Models::User.find(user[:username].strip)
  errors = []
  if retrieved_user.nil?
    errors << "ERRORS: #{user[:username]}"
    errors << "retrieval"
  else
    errors << "ERRORS: #{user[:username]}"
    if !retrieved_user.passwordHash.eql?(user[:password])
      errors << "hash"
    end
    if !retrieved_user.apikey.eql?(user[:apikey])
      errors << "apikey"
    end
  end
  puts errors.join("\n") + "\n\n" unless errors.length <= 1
  pbar.inc
end

pbar.finish