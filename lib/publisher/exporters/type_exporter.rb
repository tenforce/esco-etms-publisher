###
# TypeExporter
# copies data from one graph to another one, with some extra perks:
#  - this will only copy classes and properties that are configured (and match an optional additional filter)
#  - uses batches to copy resources
###
class Publisher::Exporters::TypeExporter
  include  Publisher::Helpers
  attr_reader :client, :application_graph, :export_graph, :sparql_prefixes

  def initialize(client, application_graph, export_graph, sparql_prefixes)
    @client = client
    @application_graph = application_graph
    @export_graph = export_graph
    @sparql_prefixes = sparql_prefixes
  end

  def export(type, config)
    concept_uris = retrieve_concept_uris(type.to_s, config)
    batched_insert_of(type.to_s, concept_uris, config)
  end

  ###
  # copies all specified optional and required properties for the specified concept uris
  # @param concept_uris, a List of concept uris
  # @param config, the normalized type specific configuration
  ###
  def batched_insert_of(type, concept_uris, config)
    i = 0
    batch_size = 200 # low size to support slow owlim or virtuoso with low timeouts
    threshold = 0.2
    log.info "#{concept_uris.size} resources match requirements"
    while i < concept_uris.size && !concept_uris.empty?
      n = i + batch_size > concept_uris.size ? concept_uris.size : i + batch_size
      uris = concept_uris[i..n]
      client.update(%(
                    #{sparql_prefixes}
                 INSERT {
                    GRAPH <#{export_graph}> {
                      #{insert_statements_for_type(config)}
                    }
                 }
                 WHERE {
                    GRAPH <#{application_graph}> {
                      #{where_statements_for_type(type, config, true)}
                      FILTER(?resource IN (#{uris.join(',')}))
                 }}
      ))
      i = n
      if n / concept_uris.size.to_f >= threshold
        log.info "inserted #{(n / concept_uris.size.to_f * 100).round(1) }% of resources"
        threshold += 0.2
      end
    end
  end

  def insert_statements_for_type(config)
    statements = []
    statements << "?resource a ?type."
    statements << "?resource ?optional_pred ?optional_obj."
    statements << config[:required_properties].map { |_, prop| "?resource #{prop['uri']} ?#{prop['varname']}." }
    statements.join("\n")
  end

  def where_statements_for_type(type, config, include_opt = false)
    statements = []
    statements << "?resource a ?type."
    statements << "?resource a #{type.start_with?('http') ? "<#{type}>" : type}."
    statements << config[:required_properties].map { |_, prop| "?resource #{prop['uri']} ?#{prop['varname']}." }
    if include_opt
      statements << "?resource ?optional_pred ?optional_obj."
      statements << "FILTER (?optional_pred IN (#{config[:optional_properties].map{|_, x| x['uri']}.<<("rdf:type").join(',')}))"
    end
    statements << config[:additional_filter]
    statements.join("\n")
  end

  ###
  # retrieves the uri's of each resource that matches the specified criteria
  # e.g is of the right type and has all required properties
  ###
  def retrieve_concept_uris(type, config)
    uris = []
    count = count(type, config)
    i = 0
    batchsize = 10_000
    until i > count
      result = client.query(%(
                            #{sparql_prefixes}
                            SELECT distinct ?resource
                            FROM <#{application_graph}>
                            WHERE {
                              #{where_statements_for_type(type, config)}
                            }
                            LIMIT #{batchsize}
                            OFFSET #{i}
                            ))
      uris += result.map { |r| "<#{r['resource'].value}>" }
      i += batchsize
    end
    uris
  end

  ###
  # counts the amount of resources that match the specified criteria
  # e.g is of the right type and has all required properties
  ###
  def count(type, config)
    client.query(%(
                 #{sparql_prefixes}
                  SELECT (count(distinct(?resource)) as ?count)
                  FROM <#{application_graph}>
                  WHERE {
                    #{where_statements_for_type(type, config)}
                  })).first["count"].value.to_i
  end
end
