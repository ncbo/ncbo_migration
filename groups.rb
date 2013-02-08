require 'progressbar'
require 'ontologies_linked_data'

require_relative 'helpers/rest_helper'

puts "Number of groups to migrate: #{RestHelper.groups.length}"
pbar = ProgressBar.new("Migrating", RestHelper.groups.length)
RestHelper.groups.each do |group|
  g             = LinkedData::Models::Group.new
  g.acronym     = RestHelper.safe_acronym(group.acronym)
  g.name        = group.name
  g.description = group.description.eql?("string") ? nil : group.description
  
  if g.valid?
    g.save
  else
    puts "Couldn't save #{g.acronym}: #{g.errors}"
  end
  
  pbar.inc
end
pbar.finish
