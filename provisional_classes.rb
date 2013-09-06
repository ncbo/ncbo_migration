require_relative 'settings'
require_relative 'helpers/rest_helper'
require 'ncbo_resolver'

resolver_options = {
  redis_host: LinkedData.settings.redis_host,
  redis_port: LinkedData.settings.redis_port
}
NCBO::Resolver.configure(resolver_options)

def save_list(old_lst, new_lst)
  old_lst.each do |val|
    if (val.length > 0)
      if val.is_a?(Hash)
        if (val.has_key?(:string))
          new_lst << val[:string]
        else
          new_lst << val[:int]
        end
      else
        new_lst << val
      end
    end
  end
end

provClasses = RestHelper.provisional_classes

provClasses.each do |opc|
  pc = LinkedData::Models::ProvisionalClass.new
  pc.label = opc.label
  new_syn = []
  old_syn = opc.synonyms
  save_list(old_syn, new_syn)

  if !new_syn.empty?
    pc.synonym = new_syn
  end

  new_def = []
  old_def = opc.definitions
  save_list(old_def, new_def)

  if !new_def.empty?
    pc.definition = new_def
  end

  old_rel = opc.relations[0][:entry]
  rel_hash = {}

  old_rel.each do |rel|
    key = rel[:string]

    if key.is_a?(Array) && key.length > 1
      key = key[0]
    end
    rel_hash[key] = rel
  end

  rel_hash.each do |key, rel|
    if key == "provisionalSubclassOf"
      if rel.has_key?(:"org.openrdf.model.URI")
        uri = rel[:"org.openrdf.model.URI"][:uriString]

        if !RestHelper.uri? uri
          ontology_rel = rel_hash["provisionalRelatedOntologyIds"]
          old_ontology_ids = []
          save_list(ontology_rel[:list], old_ontology_ids)

          if !old_ontology_ids.empty?
            old_ontology = RestHelper.latest_ontology(old_ontology_ids[0])

            if old_ontology
              uri = NCBO::Resolver::Classes.uri_from_short_id(old_ontology.abbreviation, uri)
            end
          else
            uri = nil
          end
        end

        if uri
          pc.subclassOf = RDF::URI.new(uri)
        end
      end
    elsif key == "provisionalSubmittedBy"
      old_user = RestHelper.user(rel[:int])
      new_user = LinkedData::Models::User.find(old_user.username).include(:username).first
      pc.creator = new_user
    elsif key == "provisionalPermanentId"
      if rel[:string].is_a?(Array) && rel[:string].length > 1 && !rel[:string][1].empty?
        pc.permanentId = RDF::URI.new(rel[:string][1])
      end
    elsif key == "provisionalRelatedNoteId"
      if rel[:string].is_a?(Array) && rel[:string].length > 1 && !rel[:string][1].empty?
        pc.noteId = RDF::IRI.new("#{LinkedData::Models::Note.id_prefix.to_s}#{rel[:string][1].sub('Note_', '')}")
      end
    elsif key == "provisionalRelatedOntologyIds"
      old_ontology_ids = []
      new_ontologies = []
      save_list(rel[:list], old_ontology_ids)

      old_ontology_ids.each do |old_ontology_id|
        old_ontology = RestHelper.latest_ontology(old_ontology_id)

        if old_ontology && old_ontology.abbreviation
          new_ontology = LinkedData::Models::Ontology.find(old_ontology.abbreviation).include(:acronym).first

          if new_ontology
            new_ontologies << new_ontology
          end
        end
      end
    elsif key == "provisionalCreated"
      date_created = DateTime.strptime(rel[:date], "%Y-%m-%d %H:%M:%S.%L %Z")
      pc.created = date_created
    end
  end

  if pc.valid?
    pc.save
  else
    puts "Couldn't save provisional term #{pc.label}, #{pc.errors}"
  end

end
