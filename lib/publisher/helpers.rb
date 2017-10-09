###
# Helpers
# provides general helpers
# somewhat dirty module that globalizes the (relevant) settings from the sinatra application
# you could also access Sinatra::Application.settings directly if you want
###
module Publisher::Helpers
  class SmartSparqlClient
    def query(query, options = {})
      client = Sinatra::Application.settings.sparql_client.clone
      client.query(query, options)
    end

    def update(query)
      client = Sinatra::Application.settings.sparql_client.clone
      client.update query, { endpoint: Sinatra::Application.settings.update_endpoint }
    end
  end
  CLIENT = SmartSparqlClient.new
  GRAPH = Sinatra::Application.settings.graph
  LOG = Sinatra::Application.settings.log
  SPARQL_PREFIXES = %(
      PREFIX mu:      <http://mu.semte.ch/vocabularies/core/>
      PREFIX dcterms: <http://purl.org/dc/terms/>
      PREFIX void: <http://rdfs.org/ns/void#>
    )

  def client
    CLIENT
  end

  def graph
    GRAPH
  end

  def log
    LOG
  end

  def self.publication_iri(id)
    "http://etms.tenforce.com/publications/#{id}"
  end

  def self.file_path_for(id)
    filename = "publication-#{id}.nt"
    File.join(ENV["PUBLISHER_EXPORT_PATH"], filename)
  end

  def self.is_database_up?
    begin
      CLIENT.query("ASK {?s ?p ?o}")
    rescue
      return false
    end
  end

  def self.wait_for_database
    until is_database_up?
      sleep 2
    end
  end

  def publication_iri(id)
    Publisher::Helpers::publication_iri(id)
  end

  def sparql_prefixes
    SPARQL_PREFIXES
  end
end
