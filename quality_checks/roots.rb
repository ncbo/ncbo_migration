require_relative '../settings.rb'
require_relative '../helpers/rest_helper'

bad_roots = [ ["ontology", "production", "new api"] ]
puts ["ontology".ljust(15), "production".rjust(10), "new api".rjust(10)].join("\t\t")

rest_ontologies = RestHelper.ontologies
rest_ontologies.each do |rest_ont|
  begin
    rest_roots = RestHelper.roots(rest_ont.id).length
  rescue Timeout::Error
    puts "#{rest_ont.abbreviation} timed out on REST"
    next
  rescue
    puts "#{rest_ont.abbreviation} failed on REST"
    next
  end
  
  sub = LinkedData::Models::Ontology.find(rest_ont.abbreviation).first.latest_submission rescue next
  next unless sub
  roots = sub.roots(nil,false,true).length
  
  if rest_roots.to_f / roots.to_f < 0.9 || rest_roots.to_f / roots.to_f > 1.1
    bad_roots << [rest_ont.abbreviation, rest_roots, roots]
    bad = "***"
  end
  puts ["#{rest_ont.abbreviation} #{bad}".ljust(15), rest_roots.to_s.rjust(10), roots.to_s.rjust(10)].join("\t\t")
end

puts bad_roots.each {|row| "#{row.join("\t\t")}\n"}
