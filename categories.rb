require 'ostruct'
require 'progressbar'
require 'ontologies_linked_data'

require_relative 'helpers/rest_helper'

puts "Number of categories to migrate: #{RestHelper.categories.length}"
pbar = ProgressBar.new("Migrating", RestHelper.categories.length*3)
relations = []
RestHelper.categories.each do |category|
  c         = LinkedData::Models::Category.new
  c.acronym = RestHelper.safe_acronym(category.name)
  c.name    = category.name
  
  pbar.inc
  
  if c.valid?
    c.save
  else
    puts "Couldn't save #{c.acronym}: #{c.errors}"
  end
  
  # Save for later use in assigning parents
  relations << OpenStruct.new(:child => category.id, :parent => category.parentId) unless category.parentId.nil?
  pbar.inc
end

relations.each do |relation|
  child_acronym = RestHelper.safe_acronym(RestHelper.category(relation.child).name)
  parent_acronym = RestHelper.safe_acronym(RestHelper.category(relation.parent).name)
  child = LinkedData::Models::Category.find(child_acronym)
  parent = LinkedData::Models::Category.find(parent_acronym)
  child.parentCategory = parent
  if child.valid?
    child.save
  else
    puts "Couldn't update parent for #{child.acronym}, #{child.errors}"
  end
  pbar.inc
end
pbar.finish

