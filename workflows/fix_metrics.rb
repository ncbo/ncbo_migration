require_relative '../settings'

metrics = LinkedData::Models::Metric.all
metrics_by_id = Hash.new
metrics.each do |x|
  metrics_by_id[x.id.to_s] = x
end

LinkedData::Models::OntologySubmission.where.include(:submissionStatus, :metrics).all.each do |s|
  if s.ready? && !s.metrics
    if metrics_by_id[s.id.to_s + "/metrics"]
      puts "Fixing #{s.id.to_s}"
      s.bring_remaining
      s.metrics = metrics_by_id[s.id.to_s + "/metrics"]
      s.save
      puts "Done."
    end
  end
end
