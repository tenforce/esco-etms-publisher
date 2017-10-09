class Publisher::PubOfficializer
  ESCO = RDF::Vocabulary.new('http://data.europa.eu/esco/model#')
  ETMS = RDF::Vocabulary.new('http://sem.tenforce.com/vocabularies/etms/')

  def initialize(publication)
    @publication = publication
    @reader = RDF::Reader.open(Publisher::Helpers::file_path_for(publication.id))
  end

  def update_published
    @reader.each_statement do |statement|
      if statement.predicate == RDF::URI.new("http://purl.org/iso25964/skos-thes#status")
        update_concept(statement.subject.value, etms_status(statement.object.value))
      end
    end
  end

  private

  def etms_status(status_string)
    if status_string == "released"
      "<http://sem.tenforce.com/vocabularies/etms/publicationStatusPublished>"
    else
      "<http://sem.tenforce.com/vocabularies/etms/publicationStatusDeprecated>"
    end
  end

  def update_concept(concept, newStatus)
    issued = @publication.issued
    client.update(
        %(
      WITH <#{graph}>
      DELETE { <#{concept}> <#{ETMS.hasPublicationStatus}> ?status }
      INSERT {
               <#{concept}> <#{ETMS.hasPublicationStatus}> #{newStatus};
                            <#{RDF::Vocab::DC.issued}> ?issued.
             }
      WHERE {
        <#{concept}> <#{ETMS.hasPublicationStatus}> ?status
        OPTIONAL { <#{concept}>  <#{RDF::Vocab::DC.issued}> ?date. }
        BIND (IF(BOUND(?date), ?date, STRDT("#{issued}", xsd:dateTime)) as ?issued)
      }
      ))
  end
end