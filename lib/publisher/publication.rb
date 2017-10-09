require "securerandom"

###
# Publisher::Publication
# publication ORM
###
class Publisher::Publication
  include Publisher::Helpers

  attr_accessor :name
  attr_reader :filename, :id, :created, :modified, :issued, :iri
  # values of status are "new", "running", "done", "official" and "failed"
  attr_accessor :status

  def initialize(status: "new", name:, issued: nil, filename: nil, modified: nil, created: DateTime.now, id: nil, publication: nil)
    @iri = publication
    @status = status
    @name = name
    @created = created
    @issued = issued || @created
    @filename = filename
    @modified = modified
    @id = id
  end

  def self.list(offset: 0)
    result = CLIENT.query(%(
                          #{SPARQL_PREFIXES}
      SELECT *
      FROM <#{GRAPH}>
      WHERE
       {
        ?publication a void:Dataset;
                      mu:uuid ?id;
                      dcterms:title ?name;
                      dcterms:created ?created;
                      dcterms:modified ?modified;
                      <http://dbpedia.org/ontology/status> ?status.
        OPTIONAL { ?publication dcterms:issued ?issued. }
        OPTIONAL { ?publication <http://dbpedia.org/ontology/filename> ?filename. }
      }
      OFFSET #{offset} LIMIT 50
    ))
    result.map { |r| new(r.each_binding.map{ |x,y| [x,y.value]}.to_h) }
  end

  def self.create(name:, issued:)
    pub = new(name: name, issued: issued)
    pub.persist!
    pub
  end

  def self.find(id)
    result = CLIENT.query(%(
                          #{SPARQL_PREFIXES}
      SELECT *
      FROM <#{GRAPH}>
      WHERE
       {
           ?publication mu:uuid "#{id}";
                        dcterms:title ?name;
                        dcterms:created ?created;
                        dcterms:modified ?modified;
                        <http://dbpedia.org/ontology/status> ?status.
        OPTIONAL { ?publication dcterms:issued ?issued. }
        OPTIONAL { ?publication <http://dbpedia.org/ontology/filename> ?filename. }
        BIND("#{id}" as ?id)
      }
    ))
    if result.empty?
      raise Sinatra::NotFound.new "could not find publication with id #{id}"
    end
    new(result.first.each_binding.map{ |x,y| [x,y.value]}.to_h)
  end

  def generate_file
    @status = "running"
    persist!
    async_file_generation
  end

  def official?
    @status == "official"
  end

  def download
    if filename.nil?
      nil
    else
      "/publications/#{id}/download"
    end
  end

  def to_json(*args)
    {
        type: "publications",
        id: id,
        attributes: {
            created: created,
            modified: modified,
            issued: issued,
            name: name,
            status: status,
            download: download
        }
    }.to_json(*args)
  end

  def delete!
    client.update(%(
      WITH <#{graph}>
      DELETE {  <#{iri}> ?p ?o }
      WHERE {  <#{iri}> ?p ?o }
    ))
  end

  def persist!
    if id.nil?
      # it's a new publication
      @id = SecureRandom.uuid
      @iri = Publisher::Helpers::publication_iri(id)
      insert_query
    else
      # it's an update
      update_query
    end
  end

  private

  def async_file_generation
    Thread.new do
      begin
        log.info "started generation of new publication #{id} at #{DateTime.now}"
        @filename = Publisher::FileGenerator.generate(id)
        log.info "finished generation of new publication #{id} at #{DateTime.now}"
        @status = "done"
        persist!
        Publisher::FileGenerator.RUNNING = false
      rescue StandardError => e
        @status = "failed"
        persist!
        log.error "generation of publication #{id} failed"
        log.error e.message
        log.info e.backtrace
        Publisher::FileGenerator.RUNNING = false
      ensure
        Publisher::FileGenerator.cleanup_graph(id)
      end
    end
  end

  def insert_query
    @modified = created
    client.update(%(
                  #{sparql_prefixes}
      INSERT DATA {
        GRAPH <#{graph}> {
        <#{iri}> mu:uuid "#{id}";
                 a void:Dataset;
                 dcterms:title "#{name}";
                 dcterms:created "#{created}"^^xsd:dateTime;
                 dcterms:modified "#{modified}"^^xsd:dateTime;
                 #{issued_triple}
                 #{filename_triple}
                 <http://dbpedia.org/ontology/status> "#{status}".
      }
      }
    ))
  end

  def update_query
    @modified = DateTime.now
    client.update(%(
                  #{sparql_prefixes}
      WITH <#{graph}>
      DELETE  {
        <#{iri}> ?p ?o
      }
      INSERT {
        <#{iri}> mu:uuid "#{id}";
                 a void:Dataset;
                 dcterms:title #{name.sparql_escape};
                 dcterms:created "#{created}"^^xsd:dateTime;
                 dcterms:modified "#{modified}"^^xsd:dateTime;
                 #{issued_triple}
                 #{filename_triple}
                 <http://dbpedia.org/ontology/status> "#{status}".
      }
      WHERE {
          <#{iri}> ?p ?o
        }
    ))
  end

  def self.remove_old_running_publications
    CLIENT.update(%(
      #{SPARQL_PREFIXES}
      WITH <#{GRAPH}>
      DELETE  {
        ?publication <http://dbpedia.org/ontology/status> "running".
        ?publication dcterms:modified ?modified.
      }
      INSERT {
        ?publication <http://dbpedia.org/ontology/status> "failed".
        ?publication dcterms:modified "#{DateTime.now}"^^xsd:dateTime.
      }
      WHERE {
        ?publication a void:Dataset;
                 dcterms:modified ?modified;
                 <http://dbpedia.org/ontology/status> "running".
        }
    ))
  end

  def issued_triple
    issued.nil? ? "" : "dcterms:issued \"#{issued}\"^^xsd:dateTime;"
  end

  def filename_triple
    filename.nil? ? "" : "<http://dbpedia.org/ontology/filename> \"#{filename}\";"
  end
end
