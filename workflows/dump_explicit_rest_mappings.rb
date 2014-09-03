require_relative '../settings'

def dump_all_rest_mappings() 
  rest_predicate = LinkedData::Mappings.mapping_predicates["REST"][0]
  procs = LinkedData::Models::MappingProcess.where
      .include(LinkedData::Models::MappingProcess.attributes)
      .all.select { |x| !x.date.nil? }
  
  procs.each_index do |pi|
    p = procs[pi]
    $stderr.write("#{pi+1}/#{procs.length} process ...\n")
    pgraph  = Goo::SPARQL::Triples.model_delete_triples(p)
    pgraph[0].each do |triple|
        dump_triple(triple,LinkedData::Models::MappingProcess.type_uri.to_s)
    end
    mapping_ids = []
    qmappings = <<-eos
  SELECT ?s
  WHERE { ?s <http://data.bioontology.org/metadata/process> <#{p.id.to_s}> .
  }
  eos
    epr = Goo.sparql_query_client(:main)
    mapping_ids = []
    epr.query(qmappings).each do |sol|
        mapping_ids << sol[:s]
    end

    $stderr.write("\tMappings #{mapping_ids.length}\n")
    mapping_ids.each_index do |idx|
      mapping_id = mapping_ids[idx]
      if (idx+1) % 10 == 0
        $stderr.write("\t\tprogress #{idx+1}/#{mapping_ids.length}\n")
      end


      qterms = <<-eos
  SELECT ?termId ?ontId ?classId
  WHERE { <#{mapping_id}> 
          <http://data.bioontology.org/metadata/terms> ?termId .
      ?termId <http://data.bioontology.org/metadata/ontology> ?ontId .
      ?termId <http://data.bioontology.org/metadata/term> ?classId .
  }
  eos
      urn_classes = []
      classes = []
      latest = nil
      epr.query(qterms).each do |sol_term|
          ontId, classId = sol_term[:ontId], sol_term[:classId]
          ont = LinkedData::Models::Ontology
                  .find(ontId).include(:acronym).first
          if ont.nil?
            break
          end
          acronym = ont.acronym
          latest = ont.latest_submission
          if latest.nil?
            break
          end
          cls = LinkedData::Models::Class.find(classId).in(latest).first
          if cls.nil?
            next
          end
          classes << cls
          urn_classes << RDF::URI.new(
                    LinkedData::Models::Class.urn_id(acronym,classId.to_s))

      end
      if urn_classes.length == 2
        backup_mapping = LinkedData::Models::RestBackupMapping.new
        backup_mapping.uuid = UUID.new.generate
        backup_mapping.process = p
        backup_mapping.class_urns = urn_classes
        mgraph = Goo::SPARQL::Triples.model_update_triples(backup_mapping)
        mgraph[0].each do |triple|
          dump_triple(triple,LinkedData::Models::RestBackupMapping.type_uri.to_s)
        end
        classes.each do |cls| 
          triple =  "<#{latest.id.to_s}>" +
                    " <#{cls.id.to_s}>" + 
                    " <#{rest_predicate}>" +
                    " <#{backup_mapping.id.to_s}> ."
          puts triple
          dump_triple([cls.id.to_s,rest_predicate,backup_mapping.id.to_s], latest.id.to_s)
        end
      end
    end

  end
end

def dump_triple(triple,graph)
  quad = []
  3.times do |i|
    if triple[i].respond_to?(:to_ntriples)
      quad << triple[i].to_ntriples
    else
      quad << "<#{triple[i].to_s}>"
    end
  end
  quad << "<#{graph.to_s}>"
  quad << "."
  puts quad.join(" ")
end
dump_all_rest_mappings
