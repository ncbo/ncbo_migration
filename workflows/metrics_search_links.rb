require_relative '../settings'

require 'logger'
require 'progressbar'

puts "Linking #{LinkedData::Models::Metric.where.all.length} metric objects"
LinkedData::Models::Metric.where.all.each do |m|
  m.bring_remaining
  submission_id = RDF::URI.new(m.id.to_s.split("/")[0..-2].join "/")
  submission = LinkedData::Models::OntologySubmission.find(submission_id).first
  if submission.nil?
    puts "Not found submission #{submission_id}"
  else
    submission.bring_remaining
    submission.metrics = m
    puts submission.valid?
  end
end
