require_relative 'helpers/rest_helper'

DEFAULT_PREFIX = "http://bioportal.bioontology.org/metadata/def/"
OMV_PREFIX = "http://omv.ontoware.org/2005/05/ontology#"
OMV_ATTRS = %w(acronym creationDate description documentation hasDomain hasOntologyLanguage name version format abbreviation displayLabel)
SKIP_ATTRS = %w(userAcl)

ATTR_NAME_MAPPING = {
  "dateReleased" => "creationDate",
  "dateCreated" => "timestampCreation",
  "contactEmail" => "hasContactEmail",
  "contactName" => "hasContactName",
  "statusId" => "statusID",
  "preferredNameSlot" => "preferredNameProperty",
  "synonymSlot" => "synonymProperty",
  "documentationSlot" => "documentationProperty",
  "format" => "hasOntologyLanguage",
  "userIds" => "administeredBy",
  "homepage" => "urlHomepage",
  "ontologyId" => "isVersionOfVirtualOntology",
  "abbreviation" => "acronym",
  "displayLabel" => "name"
}

ATTR_VALUE_MAPPING = {
  "userIds" => "<http://bioportal.bioontology.org/users/%value%>",
  "isVersionOfVirtualOntology" => "<http://bioportal.bioontology.org/ontologies/%value%>",
  "format" => "<http://omv.ontoware.org/2005/05/ontology#%value%>"
}

RDF_LITERAL = {
  String => lambda {|e| "\"#{e.strip.gsub('"', '\"').gsub(/\r\n/, "\\n").gsub(/\n/, "\\n").gsub(/\t/, "\\t")}\"^^<http://www.w3.org/2001/XMLSchema#string>"},
  Time => lambda {|e| "\"#{e.utc.iso8601}\"^^<http://www.w3.org/2001/XMLSchema#dateTime>"}
}

def convert_attr_name(attr_name)
  conversion = ATTR_NAME_MAPPING[attr_name.to_s]
  attr_name = conversion unless conversion.nil?
  
  if OMV_ATTRS.include?(attr_name)
    prefix = OMV_PREFIX
  else
    prefix = DEFAULT_PREFIX
  end
  
  "<#{prefix}#{attr_name}>"
end

def convert_attr_value(attr_name, attr_value)
  attr_value = Time.parse(attr_value) rescue attr_value
  conversion = ATTR_VALUE_MAPPING[attr_name.to_s]
  rdf_conversion = RDF_LITERAL[attr_value.class]
  if conversion
    attr_value = conversion.sub("%value%", attr_value.to_s)
  elsif rdf_conversion
    attr_value = rdf_conversion.call(attr_value) unless rdf_conversion.nil?
  end
  attr_value = attr_name.to_s.start_with?("is") && !attr_value.is_a?(TrueClass) && !attr_value.is_a?(FalseClass) ? attr_value > 0 : attr_value
  attr_value
end

def get_versions(ont, times = 0)
  times += 1
  raise Exception("Too many retries") if times > 10
  versions = RestHelper.ontology_versions(ont.ontologyId) rescue get_versions(ont, times)
  versions
end

ontologies = RestHelper.ontologies
views = RestHelper.views
ont_and_views = ontologies + views

submissions = []
ont_and_views.each do |ont|
  versions = RestHelper.ontology_versions(ont.ontologyId)
  versions = versions.kind_of?(Array) ? versions : [versions]
  submissions = submissions + versions
end

submissions = ont_and_views if submissions.nil?

output = StringIO.new
output << "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .\n"
triple_prefix = "    "
triple_delim = " ;\n"
object_delim = "    a <http://omv.ontoware.org/2005/05/ontology#Ontology> .\n\n\n"
virtual_delim = "    a <http://bioportal.bioontology.org/metadata/def/VirtualOntology> .\n\n\n"
virtual_onts = {}
submissions.each do |o|
  output << "<http://bioportal.bioontology.org/ontologies/#{o.id}>\n"
  o_hash = o.marshal_dump
  o_hash.each do |attr_name, attr_value|
    next if attr_value.eql?("") || (attr_value.is_a?(Array) && attr_value.first.eql?("")) || SKIP_ATTRS.include?(attr_name.to_s)
    if attr_value.is_a?(Array)
      values = attr_value.first.first[1]
      values = values.is_a?(Array) ? values : [ values ]
      values.each do |value|
        output << "#{triple_prefix}#{convert_attr_name(attr_name)} #{convert_attr_value(attr_name, value)}#{triple_delim}"
      end
    else
      output << "#{triple_prefix}#{convert_attr_name(attr_name)} #{convert_attr_value(attr_name, attr_value)}#{triple_delim}"
    end
  end
  output << object_delim
  
  # Store ids
  virtual_onts[o.ontologyId] ||= []
  virtual_onts[o.ontologyId] << o.id
end

virtual_onts.each do |virtual_id, version_ids|
  # Virtual statement
  output << "<http://bioportal.bioontology.org/ontologies/#{virtual_id}> a <http://bioportal.bioontology.org/metadata/def/VirtualOntology> ;\n"
  output << "    <http://bioportal.bioontology.org/metadata/def/id> #{virtual_id} ;\n"
  version_ids.each do |version_id|
    output << "    <http://bioportal.bioontology.org/metadata/def/hasVersion> <http://bioportal.bioontology.org/ontologies/#{version_id}> ;\n"
  end
  output << "    .\n\n"
end  

# puts output.string
  
file = File.new("./ont_metadata.turtle", "w+")
file.write(output.string)
file.close

#command to put file in process
#curl -T ont_metadata.turtle -H 'Content-Type: application/x-turtle' http://ncbostage-fsmaster1:8081/data/http://bioportal.bioontology.org/ontologies/metadata
