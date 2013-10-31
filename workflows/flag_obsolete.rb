require_relative '../settings'



## this script cannot be run in production until staging branch
## for obsolete terms is merged
logger = Logger.new(STDOUT)
LinkedData::Models::Ontology.where.include(:acronym).all.each do |o|
  s = o.latest_submission(status: :ready)
  if s
    s.bring_remaining
    if s.obsoleteParent || s.obsoleteProperty
      puts "flag obsolete terms for submission #{s.id.to_s}"
      s.generate_obsolete_classes(s.data_folder, logger)
      puts "Done."
    end
  end 
end
