require_relative 'settings'

require 'progressbar'
require 'ontologies_linked_data'

require_relative 'helpers/rest_helper'

require 'mysql2'
require 'ontologies_linked_data'
require 'progressbar'

notification_types = {3 => "ALL", 10 => "NOTES"}

client = Mysql2::Client.new(host: USERS_DB_HOST, username: USERS_DB_USERNAME, password: USERS_DB_PASSWORD, database: "bioportal")

subscription_query = <<-EOS
SELECT * from ncbo_user_subscriptions
EOS

subscriptions = client.query(subscription_query)

puts "Number of subscriptions to migrate: #{subscriptions.count}"
pbar = ProgressBar.new("Migrating", subscriptions.count)
errors = []
subscriptions.each do |subscription|
  begin
    user_old = RestHelper.user(subscription['user_id'])
  rescue
    errors << "Bad user #{subscription}"
    next
  end
  
  begin
    ont_old = RestHelper.latest_ontology(subscription['ontology_id'])
  rescue
    errors << "Bad ontology #{subscription}"
    next
  end

  notification_type = LinkedData::Models::Users::NotificationType.find(notification_types[subscription['notification_type']]).first
  user = LinkedData::Models::User.find(user_old.username).include(LinkedData::Models::User.attributes).first
  ont = LinkedData::Models::Ontology.find(ont_old.abbreviation).first
  
  binding.pry if user.nil? || ont.nil?
  
  new_subscription = LinkedData::Models::Users::Subscription.new
  new_subscription.ontology = ont
  new_subscription.notification_type = notification_type
  new_subscription.save
  
  user_subscriptions = user.subscription.dup
  user_subscriptions ||= []
  user_subscriptions << new_subscription
  
  user.subscription = user_subscriptions
  user.save
  
  # Test
  user = LinkedData::Models::User.find(user_old.username).include(LinkedData::Models::User.attributes).first
  errors << "Subscription not updated #{subscription}" if user.subscription.nil? || user.subscription.empty?
  
  pbar.inc
end
pbar.finish

puts errors.join("\n")